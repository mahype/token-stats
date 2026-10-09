using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using TokenStats.Model;
using TokenStats.Usage;

namespace TokenStats.UI;

/// <summary>Seite „Verbrauch“: Tokens und API-Vergleichswert je Zeitraum (SPEC §3.5).</summary>
sealed class UsageView(
    Palette p, ConsumptionStore consumption, string providerId, bool showMoney, int? subscription,
    UsagePeriod period, Action<UsagePeriod> selectPeriod)
{
    public UIElement Build()
    {
        if (!ConsumptionStore.ProviderIds.Contains(providerId))
            return Placeholder("Für diesen Anbieter gibt es noch keine Verbrauchsauswertung.");

        var column = Ui.Column(14, PeriodPicker());
        if (consumption.Summary(providerId, period) is { } summary)
        {
            if (summary.Total.IsZero)
                Ui.Add(column, Placeholder("Keine Einträge in diesem Zeitraum."), 14);
            else
                foreach (var element in Content(summary)) Ui.Add(column, element, 14);
        }
        else if (consumption.Failure is { } failure)
        {
            Ui.Add(column, Placeholder(failure), 14);
        }
        else
        {
            Ui.Add(column, Placeholder("Verbrauch wird eingelesen …"), 14);
        }
        return column;
    }

    UIElement PeriodPicker()
    {
        var row = Ui.Row(12);
        foreach (var option in UsagePeriods.All)
        {
            var isOn = option == period;
            var label = Ui.Text(option.Label(), 11.5, isOn ? p.Primary : p.Secondary, isOn ? FontWeights.Bold : FontWeights.Normal);
            Ui.Add(row, Ui.Clickable(label, () => selectPeriod(option)), 12);
        }
        return row;
    }

    IEnumerable<UIElement> Content(UsageSummary summary)
    {
        var tiles = new Grid();
        tiles.ColumnDefinitions.Add(new ColumnDefinition());
        tiles.Children.Add(Tile("Tokens", Format.Tokens(summary.Total.Total),
                                $"{Format.Tokens(summary.Total.CacheRead)} davon Cache-Lesen"));
        if (showMoney)
        {
            tiles.ColumnDefinitions.Add(new ColumnDefinition());
            var money = Tile("API-Vergleichswert", Format.Money(summary.Value) + (summary.HasUnpriced ? "*" : ""),
                             subscription is { } dollars ? $"Abo {dollars} $ / Monat" : "berechnet");
            money.Margin = new Thickness(10, 0, 0, 0);
            Grid.SetColumn(money, 1);
            tiles.Children.Add(money);
        }
        yield return tiles;

        if (summary.Days.Count > 1) yield return DayChart(summary.Days);

        var models = new StackPanel();
        foreach (var line in summary.Models)
        {
            models.Children.Add(ModelRow(line));
            models.Children.Add(Ui.Divider(p.Separator));
        }
        var total = Ui.Spread(
            Ui.Text($"{period.Label()} · {Format.Tokens(summary.Total.Total)} Tokens", 12, p.Primary, FontWeights.Bold),
            showMoney ? Ui.Text(Format.Money(summary.Value), 12, p.Primary, FontWeights.Bold) : null);
        total.Margin = new Thickness(0, 8, 0, 0);
        models.Children.Add(total);
        yield return models;

        yield return Ui.Wrapped(Footnote(summary), 10.5, p.Secondary);
    }

    string Footnote(UsageSummary summary)
    {
        var text = "Tokenzahlen aus den Session-Logs dieses Rechners – Nutzung auf anderen Geräten fehlt";
        if (!showMoney) return text + ".";
        var asOf = consumption.Prices.AsOf is { } date ? $" (Stand {date.ToString("MM/yyyy", Format.Culture)})" : "";
        text += $" × Listenpreis{asOf}, inkl. Cache-Tarife. Keine Abrechnungsdaten – nur, was derselbe Verbrauch über die API gekostet hätte.";
        if (summary.HasUnpriced) text += " * Modelle ohne Listenpreis sind nicht eingerechnet.";
        return text;
    }

    UIElement Placeholder(string text)
    {
        var block = Ui.Wrapped(text, 11.5, p.Secondary);
        block.TextAlignment = TextAlignment.Center;
        block.Margin = new Thickness(0, 24, 0, 24);
        return block;
    }

    Border Tile(string title, string value, string detail)
    {
        var caption = Ui.Text(title.ToUpper(Format.Culture), 10, p.Secondary);
        return new Border
        {
            CornerRadius = new CornerRadius(8),
            Background = p.Control,
            BorderBrush = p.Separator,
            BorderThickness = new Thickness(1),
            Padding = new Thickness(11, 9, 11, 9),
            Child = Ui.Column(2, caption, Ui.Text(value, 17, p.Primary, FontWeights.Bold), Ui.Text(detail, 10.5, p.Secondary)),
        };
    }

    /// <summary>Eine Säule pro Tag, der heutige Tag hervorgehoben.</summary>
    UIElement DayChart(List<UsageSummary.DayTotal> days)
    {
        var peak = Math.Max(days.Max(day => day.Tokens), 1);
        var showLabels = days.Count <= 7;
        const double barArea = 56;
        var spacing = days.Count > 14 ? 2.0 : 6.0;

        var grid = new Grid { Height = showLabels ? 72 : 56 };
        grid.RowDefinitions.Add(new RowDefinition());
        if (showLabels) grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        for (var index = 0; index < days.Count; index++)
        {
            var day = days[index];
            var isToday = index == days.Count - 1;
            grid.ColumnDefinitions.Add(new ColumnDefinition());

            var height = day.Tokens > 0 ? Math.Max(barArea * day.Tokens / peak, 2) : 0;
            var bar = new Border
            {
                Height = height,
                VerticalAlignment = VerticalAlignment.Bottom,
                CornerRadius = new CornerRadius(3, 3, 0, 0),
                Background = p.Accent,
                Opacity = isToday ? 1 : 0.55,
                Margin = new Thickness(index == 0 ? 0 : spacing / 2, 0, index == days.Count - 1 ? 0 : spacing / 2, 0),
            };
            var date = day.Day.ToDateTime(TimeOnly.MinValue);
            // Tooltip über die ganze Spalte, nicht nur über die (evtl. winzige) Säule.
            var cell = new Border
            {
                Background = Brushes.Transparent,
                Child = bar,
                ToolTip = $"{date.ToString("dddd, d. MMMM", Format.Culture)}: {Format.Tokens(day.Tokens)} Tokens",
            };
            Grid.SetColumn(cell, index);
            grid.Children.Add(cell);

            if (showLabels)
            {
                var label = Ui.Text(date.ToString("ddd", Format.Culture), 9.5, isToday ? p.Primary : p.Secondary,
                                    isToday ? FontWeights.Bold : FontWeights.Normal);
                label.HorizontalAlignment = HorizontalAlignment.Center;
                label.Margin = new Thickness(0, 4, 0, 0);
                Grid.SetColumn(label, index);
                Grid.SetRow(label, 1);
                grid.Children.Add(label);
            }
        }
        return grid;
    }

    UIElement ModelRow(UsageSummary.ModelLine line)
    {
        var counts = line.Counts;
        var detail = Ui.Text($"{Format.Tokens(counts.Input)} in · {Format.Tokens(counts.Output)} out · {Format.Tokens(counts.Cache)} Cache", 10.5, p.Secondary);
        detail.ToolTip = $"Cache-Schreiben {Format.Tokens(counts.CacheWrite)} · Cache-Lesen {Format.Tokens(counts.CacheRead)}";
        var name = Ui.Column(2, Ui.Text(ModelName.Display(line.Model), 12, p.Primary, FontWeights.SemiBold), detail);
        UIElement? value = showMoney
            ? Ui.Text(line.Value is { } amount ? Format.Money(amount) : "ohne Preis", 12,
                      line.Value is null ? p.Secondary : p.Primary, FontWeights.SemiBold)
            : null;
        var row = Ui.Spread(name, value, VerticalAlignment.Top);
        row.Margin = new Thickness(0, 7, 0, 7);
        return row;
    }
}

using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using TokenStats.Model;
using TokenStats.Providers;
using TokenStats.Usage;

namespace TokenStats.UI;

public enum PopupPage { Limits, Usage }

/// <summary>
/// Inhalt des Popups, 372 px breit: Kopf mit Seitenwahl · Tabs je Client · Seite · Fußzeile (SPEC §3).
/// Wird bei jeder Änderung komplett neu aufgebaut – so bleibt der Code nah an den SwiftUI-Views.
/// </summary>
public sealed class PopupView
{
    public const double Width = 372;
    const int MaxVisibleTabs = 4;
    /// <summary>Seitenrand aller Blöcke im Popup.</summary>
    const double Inset = 16;

    readonly UsageStore store;
    readonly ConsumptionStore consumption;
    readonly AppSettings settings;
    readonly Action openSettings;

    public Palette Palette { get; set; } = new(SystemTheme.AppsDark);
    public Func<DateTimeOffset> Now { get; set; } = () => DateTimeOffset.Now;

    string? selectedId;
    /// <summary>Beim Öffnen steht immer „Limits“ – die Auswahl wird absichtlich nicht gemerkt.</summary>
    PopupPage page;
    UsagePeriod period = UsagePeriod.Week;

    public event Action? NeedsRender;

    public PopupView(UsageStore store, ConsumptionStore consumption, AppSettings settings, Action openSettings)
    {
        this.store = store;
        this.consumption = consumption;
        this.settings = settings;
        this.openSettings = openSettings;
    }

    public void Reset(string? selected = null, PopupPage startPage = PopupPage.Limits)
    {
        selectedId = selected;
        page = startPage;
        period = UsagePeriod.Week;
    }

    void Update(Action change)
    {
        change();
        NeedsRender?.Invoke();
    }

    public FrameworkElement Build()
    {
        var p = Palette;
        var providers = store.SortedProviders;
        var selected = providers.FirstOrDefault(provider => provider.Id == selectedId) ?? providers.FirstOrDefault();

        var root = new StackPanel { Width = Width };
        root.Children.Add(Header());
        if (providers.Count == 0)
        {
            root.Children.Add(EmptyState());
        }
        else
        {
            root.Children.Add(TabBar(providers, selected?.Id));
            root.Children.Add(Ui.Divider(p.Separator));
            if (selected is not null) root.Children.Add(ProviderPage(selected));
        }
        root.Children.Add(Ui.Divider(p.Separator));
        root.Children.Add(Footer(selected is null ? null : store.State(selected.Id).Snapshot?.Account));
        return root;
    }

    // Kopf

    UIElement Header()
    {
        var p = Palette;
        var title = Ui.Row(8, new RobotIcon { Foreground = p.Primary }, Ui.Text("Token Stats", 13.5, p.Primary, FontWeights.Bold));
        var header = Ui.Spread(title, PageSwitch());
        header.Margin = new Thickness(Inset, 14, Inset, 12);
        return header;
    }

    /// <summary>Schlanker Umschalter in der Kopfzeile – bewusst leiser als ein Segmented Control.</summary>
    UIElement PageSwitch()
    {
        var p = Palette;
        var row = Ui.Row(2);
        foreach (var (option, label) in new[] { (PopupPage.Limits, "Limits"), (PopupPage.Usage, "Verbrauch") })
        {
            var isOn = option == page;
            var chip = new Border
            {
                CornerRadius = new CornerRadius(10),
                Padding = new Thickness(8, 2, 8, 3),
                Background = isOn ? p.Control : Brushes.Transparent,
                Child = Ui.Text(label, 11, isOn ? p.Primary : p.Secondary, isOn ? FontWeights.SemiBold : FontWeights.Normal),
            };
            Ui.Add(row, Ui.Clickable(chip, () => Update(() => page = option)), 2);
        }
        return new Border { CornerRadius = new CornerRadius(12), Padding = new Thickness(2), Background = p.Fill, Child = row };
    }

    // Tabs

    UIElement TabBar(List<IUsageProvider> providers, string? selected)
    {
        var p = Palette;
        var row = Ui.Row(2);
        row.Margin = new Thickness(Inset - 10, 0, Inset - 10, 0);
        foreach (var provider in providers.Take(MaxVisibleTabs))
        {
            var isActive = provider.Id == selected;
            var severity = store.State(provider.Id).Snapshot?.TightestWindow?.Severity;
            var dot = new System.Windows.Shapes.Ellipse
            {
                Width = 5, Height = 5, VerticalAlignment = VerticalAlignment.Center,
                Fill = severity is { } s ? p.SeverityBrush(s) : p.Secondary,
                Opacity = severity is null ? 0.4 : 1,
            };
            var tab = new Border
            {
                Padding = new Thickness(10, 7, 10, 7),
                BorderThickness = new Thickness(0, 0, 0, 2),
                BorderBrush = isActive ? p.Accent : Brushes.Transparent,
                Child = Ui.Row(5, dot, Ui.Text(provider.DisplayName, 12, isActive ? p.Primary : p.Secondary, FontWeights.SemiBold)),
            };
            var id = provider.Id;
            Ui.Add(row, Ui.Clickable(tab, () => Update(() => selectedId = id)), 2);
        }

        var overflow = providers.Skip(MaxVisibleTabs).ToList();
        if (overflow.Count > 0)
        {
            var menu = new ContextMenu();
            foreach (var provider in overflow)
            {
                var id = provider.Id;
                var item = new MenuItem { Header = provider.DisplayName };
                item.Click += (_, _) => Update(() => selectedId = id);
                menu.Items.Add(item);
            }
            var more = new Border { Padding = new Thickness(10, 7, 10, 9), Child = Ui.Text($"+{overflow.Count}", 11.5, p.Secondary) };
            more.ContextMenu = menu;
            Ui.Add(row, Ui.Clickable(more, () =>
            {
                menu.PlacementTarget = more;
                menu.Placement = PlacementMode.Bottom;
                menu.IsOpen = true;
            }), 2);
        }
        return row;
    }

    UIElement EmptyState()
    {
        var p = Palette;
        var hint = Ui.Wrapped("Token Stats sucht nach Claude Code (%USERPROFILE%\\.claude) und Codex (%USERPROFILE%\\.codex).", 11, p.Secondary);
        hint.TextAlignment = TextAlignment.Center;
        var title = Ui.Text("Kein Anbieter gefunden", 12.5, p.Primary, FontWeights.SemiBold);
        title.HorizontalAlignment = HorizontalAlignment.Center;
        var column = Ui.Column(6, title, hint);
        column.Margin = new Thickness(24);
        return column;
    }

    // Fußzeile

    UIElement Footer(AccountInfo? account)
    {
        var p = Palette;
        UIElement left = new Border();
        if (account?.Name is { Length: > 0 } name)
        {
            var avatar = new Border
            {
                Width = 19, Height = 19, CornerRadius = new CornerRadius(9.5), Background = p.Accent,
                Child = new TextBlock
                {
                    Text = name[..1].ToUpperInvariant(), FontFamily = Ui.Font, FontSize = 10, FontWeight = FontWeights.Bold,
                    Foreground = p.IsDark ? Brushes.Black : Brushes.White,
                    HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
                },
            };
            var label = Ui.Text(name, 11.5, p.Primary, FontWeights.SemiBold);
            label.VerticalAlignment = VerticalAlignment.Center;
            left = Ui.Row(7, avatar, label);
            ((FrameworkElement)left).Margin = new Thickness(4, 0, 4, 0);
        }

        var right = Ui.Row(8);
        if (store.LastUpdate is { } last)
        {
            var ago = Ui.Text(Format.Ago(last, Now()), 10.5, p.Secondary);
            ago.VerticalAlignment = VerticalAlignment.Center;
            Ui.Add(right, ago, 8);
        }
        var refreshContent = store.Loading.Count == 0
            ? (UIElement)Ui.Icon("", 12, p.Secondary)
            : Ui.Text("…", 12, p.Secondary, FontWeights.Bold);
        Ui.Add(right, FooterButton(refreshContent, "Aktualisieren", () => store.Refresh(manual: true)), 8);
        Ui.Add(right, FooterButton(
            Ui.Row(5, Ui.Icon("", 12, p.Secondary), Ui.Text("Einstellungen", 11.5, p.Secondary, FontWeights.SemiBold)),
            "Einstellungen (Strg+,)", openSettings), 8);

        var footer = Ui.Spread(left, right);
        return new Border { Background = p.Footer, Padding = new Thickness(Inset - 4, 10, Inset - 4, 10), Child = footer };
    }

    UIElement FooterButton(UIElement content, string help, Action action)
    {
        var p = Palette;
        var border = new Border
        {
            MinWidth = 26, MinHeight = 26,
            Padding = new Thickness(7, 0, 7, 0),
            CornerRadius = new CornerRadius(6),
            Background = p.Control,
            BorderBrush = p.Separator,
            BorderThickness = new Thickness(1),
            Child = content,
        };
        if (content is FrameworkElement element)
        {
            element.HorizontalAlignment = HorizontalAlignment.Center;
            element.VerticalAlignment = VerticalAlignment.Center;
        }
        return Ui.Clickable(border, action, help);
    }

    // Seiten „Limits“ und „Verbrauch“

    UIElement ProviderPage(IUsageProvider provider)
    {
        var p = Palette;
        var state = store.State(provider.Id);
        var column = Ui.Column(16);
        column.Margin = new Thickness(Inset, 16, Inset, 18);

        var title = Ui.Row(8, Ui.Text(provider.DisplayName, 13, p.Primary, FontWeights.Bold));
        if (state.Snapshot?.Account?.Plan is { } plan)
        {
            var planText = Ui.Text(plan, 11, p.Secondary);
            planText.FontFamily = new FontFamily("Cascadia Mono, Consolas");
            planText.VerticalAlignment = VerticalAlignment.Center;
            Ui.Add(title, planText, 8);
        }
        UIElement? chip = null;
        if (page == PopupPage.Limits && state.Snapshot?.TightestWindow is { } tightest)
        {
            var color = p.SeverityBrush(tightest.Severity);
            chip = new Border
            {
                CornerRadius = new CornerRadius(9), BorderBrush = color, BorderThickness = new Thickness(1),
                Padding = new Thickness(7, 1, 7, 1),
                Child = Ui.Text(Format.Percent(tightest.Percent), 10.5, color, FontWeights.SemiBold),
            };
        }
        Ui.Add(column, Ui.Spread(title, chip), 16);

        if (page == PopupPage.Usage)
        {
            var view = new UsageView(Palette, consumption, provider.Id, settings.ShowMoney,
                                     SubscriptionPrice.Dollars(provider.Id, state.Snapshot?.Account?.Plan), period,
                                     selectedPeriod => Update(() => period = selectedPeriod));
            Ui.Add(column, view.Build(), 16);
        }
        else
        {
            foreach (var element in Limits(state, store.Loading.Contains(provider.Id)))
                Ui.Add(column, element, 16);
        }
        return column;
    }

    IEnumerable<UIElement> Limits(UsageStore.ProviderState state, bool isLoading)
    {
        var p = Palette;
        if (StatusLine(state) is { } status) yield return status;

        if (state.Snapshot is { } snapshot)
        {
            var meters = Ui.Column(18);
            foreach (var window in snapshot.Windows) Ui.Add(meters, MeterRow(window), 18);
            yield return meters;
            if (snapshot.Extras.Count > 0)
            {
                yield return Ui.Divider(p.Separator);
                var pills = new WrapPanel();
                foreach (var extra in snapshot.Extras)
                {
                    var text = Ui.Text(extra.Text, 11, p.Secondary);
                    text.FontFamily = new FontFamily("Cascadia Mono, Consolas");
                    pills.Children.Add(new Border
                    {
                        CornerRadius = new CornerRadius(6), Background = p.Fill,
                        Padding = new Thickness(9, 4, 9, 4), Margin = new Thickness(0, 0, 8, 4), Child = text,
                    });
                }
                yield return pills;
            }
        }
        else if (isLoading)
        {
            var loading = Ui.Text("Wird abgefragt …", 11, p.Secondary);
            loading.HorizontalAlignment = HorizontalAlignment.Center;
            loading.Margin = new Thickness(0, 20, 0, 20);
            yield return loading;
        }
    }

    /// <summary>Hinweis bei Rate-Limit oder Fehler – die letzten Werte bleiben darunter sichtbar.</summary>
    UIElement? StatusLine(UsageStore.ProviderState state)
    {
        var p = Palette;
        string glyph, text;
        Severity severity;
        if (state.RetryAt is { } retryAt && state.IsRateLimited)
            (glyph, text, severity) = ("", $"Abfrage pausiert (Rate-Limit) · wieder ab {Format.Reset(retryAt, Now())}", Severity.Warn);
        else if (state.Error is { } error)
            (glyph, text, severity) = ("", state.Snapshot is null ? error : $"{error} Zeige letzten Stand.", Severity.Crit);
        else
            return null;
        var color = p.SeverityBrush(severity);
        var icon = Ui.Icon(glyph, 11, color);
        icon.VerticalAlignment = VerticalAlignment.Top;
        icon.Margin = new Thickness(0, 2, 0, 0);
        var label = Ui.Wrapped(text, 11, color);
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        label.Margin = new Thickness(6, 0, 0, 0);
        Grid.SetColumn(label, 1);
        grid.Children.Add(icon);
        grid.Children.Add(label);
        return grid;
    }

    /// <summary>Eine Meter-Zeile mit Balken, Pace-Marke und Reset-Zeit (SPEC §3.4).</summary>
    UIElement MeterRow(LimitWindow window)
    {
        var p = Palette;
        var now = Now();
        var elapsed = window.ElapsedFraction(now);
        var color = p.SeverityBrush(window.Severity);

        var name = new TextBlock { FontFamily = Ui.Font, TextTrimming = TextTrimming.CharacterEllipsis };
        name.Inlines.Add(new System.Windows.Documents.Run(window.Name) { FontSize = 12.5, FontWeight = FontWeights.SemiBold, Foreground = p.Primary });
        if (window.ScopeNote is { } note)
            name.Inlines.Add(new System.Windows.Documents.Run($"  {note}") { FontSize = 11, Foreground = p.Secondary });
        var top = Ui.Spread(name, Ui.Text(Format.Percent(window.Percent), 12.5, color, FontWeights.Bold), VerticalAlignment.Bottom);

        var bar = new MeterBar(window.Percent, elapsed, color, p.Fill, p.Primary);

        UIElement reset = window.ResetsAt is { } resetsAt ? Ui.Text($"Reset {Format.Reset(resetsAt, now)}", 11, p.Secondary) : new Border();
        UIElement? pace = null;
        if (elapsed is { } e && window.WindowLength is { } length)
        {
            var onPace = Math.Abs(window.Percent - e) < Format.PaceTolerance;
            pace = Ui.Text(Format.Pace(window.Percent, e, length), 11, onPace ? p.Secondary : color,
                           onPace ? FontWeights.Normal : FontWeights.SemiBold);
        }
        return Ui.Column(4, top, bar, Ui.Spread(reset, pace));
    }
}

/// <summary>
/// Balken mit Pace-Marke; der Abstand zwischen Füllstand und Marke ist schraffiert (SPEC §3.4):
/// kräftig, wenn der Verbrauch der Zeit voraus ist, blass, wenn Kontingent liegen bleibt.
/// </summary>
public sealed class MeterBar : FrameworkElement
{
    const double BarHeight = 6;
    readonly double percent;
    readonly double? elapsed;
    readonly Brush color, track, marker;

    public MeterBar(double percent, double? elapsed, Brush color, Brush track, Brush marker)
    {
        this.percent = percent;
        this.elapsed = elapsed;
        this.color = color;
        this.track = track;
        this.marker = marker;
        Height = 10;
        SnapsToDevicePixels = true;
    }

    protected override void OnRender(DrawingContext context)
    {
        var width = ActualWidth;
        var top = (ActualHeight - BarHeight) / 2;
        var used = Math.Clamp(percent, 0, 1);
        var showGap = elapsed is { } value && Math.Abs(used - value) >= Format.PaceTolerance;

        var capsule = new RectangleGeometry(new Rect(0, top, width, BarHeight), BarHeight / 2, BarHeight / 2);
        context.PushClip(capsule);
        context.DrawRectangle(track, null, new Rect(0, top, width, BarHeight));
        context.DrawRectangle(color, null, new Rect(0, top, width * Math.Min(used, elapsed ?? used), BarHeight));
        if (elapsed is { } elapsedValue && showGap)
        {
            var ahead = used > elapsedValue;
            var gap = new Rect(width * Math.Min(used, elapsedValue), top, width * Math.Abs(used - elapsedValue), BarHeight);
            context.PushClip(new RectangleGeometry(gap));
            context.PushOpacity(ahead ? 1 : 0.6);
            if (ahead)
            {
                context.PushOpacity(0.55);
                context.DrawRectangle(color, null, gap);
                context.Pop();
            }
            // Diagonale Schraffur.
            var pen = new Pen(color, 1.5);
            for (var x = gap.Left - BarHeight; x < gap.Right; x += 4)
                context.DrawLine(pen, new Point(x, gap.Bottom), new Point(x + BarHeight, gap.Top));
            context.Pop();
            context.Pop();
        }
        context.Pop();

        if (elapsed is { } mark)
        {
            context.PushOpacity(0.45);
            context.DrawRectangle(marker, null, new Rect(width * mark - 1, 0, 2, ActualHeight));
            context.Pop();
        }
    }
}

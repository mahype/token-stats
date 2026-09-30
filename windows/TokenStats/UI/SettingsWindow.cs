using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using TokenStats.Model;
using TokenStats.Usage;

namespace TokenStats.UI;

/// <summary>Einstellungsfenster, Abschnitte „Anzeige“, „Verbrauch“, „Aktualisierung“ und „Info“ (SPEC §4).</summary>
public sealed class SettingsWindow : Window
{
    static readonly double[] Intervals = [300, 600, 900, 1800, 3600];

    readonly AppSettings settings;
    readonly UsageStore store;
    readonly ConsumptionStore consumption;

    public SettingsWindow(AppSettings settings, UsageStore store, ConsumptionStore consumption)
    {
        this.settings = settings;
        this.store = store;
        this.consumption = consumption;

        Title = "Token Stats – Einstellungen";
        Width = 480;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Content = Build();
    }

    UIElement Build()
    {
        var root = new StackPanel { Margin = new Thickness(24, 16, 24, 24) };

        Section(root, "Anzeige");
        // Auswahlliste statt Radiobuttons: Fluent gibt jedem RadioButton 120 px Mindestbreite, drei passen nicht in die Spalte.
        var modes = new ComboBox { MinWidth = 220 };
        foreach (var mode in MenuBarModes.All) modes.Items.Add(mode.Label());
        modes.SelectedIndex = Array.IndexOf(MenuBarModes.All, settings.MenuBarMode);
        modes.SelectionChanged += (_, _) => settings.MenuBarMode = MenuBarModes.All[modes.SelectedIndex];
        Field(root, "Tray-Symbol", modes);

        var windowChoice = new ComboBox { MinWidth = 220 };
        windowChoice.Items.Add(new ComboBoxItem { Content = "Knappstes Limit", Tag = null });
        foreach (var provider in store.Providers)
            foreach (var window in store.State(provider.Id).Snapshot?.Windows ?? [])
                windowChoice.Items.Add(new ComboBoxItem { Content = $"{provider.DisplayName} · {window.Name}", Tag = $"{provider.Id}/{window.Id}" });
        windowChoice.SelectedItem = windowChoice.Items.Cast<ComboBoxItem>().FirstOrDefault(item => (string?)item.Tag == settings.FixedWindow)
                                    ?? windowChoice.Items[0];
        windowChoice.SelectionChanged += (_, _) => settings.FixedWindow = (string?)((ComboBoxItem)windowChoice.SelectedItem).Tag;
        Field(root, "Angezeigter Wert", windowChoice);

        Check(root, "Zustandsfarbe im Icon verwenden", settings.UseStateColor, value => settings.UseStateColor = value);
        Check(root, "API-Vergleichswert in Geld anzeigen", settings.ShowMoney, value => settings.ShowMoney = value);
        Check(root, "Bei Anmeldung starten", settings.LaunchAtLogin, value => settings.LaunchAtLogin = value);

        Section(root, "Verbrauch");
        var billing = new ComboBox { MinWidth = 90 };
        for (var day = 1; day <= 31; day++) billing.Items.Add($"{day}.");
        billing.SelectedIndex = settings.BillingDay - 1;
        billing.SelectionChanged += (_, _) =>
        {
            settings.BillingDay = billing.SelectedIndex + 1;
            consumption.Refresh();
        };
        Field(root, "Stichtag des Abos", billing);
        Note(root, "Beginn des Zeitraums „Abrechnungsmonat“. In kürzeren Monaten gilt der Monatsletzte.");

        Section(root, "Aktualisierung");
        var interval = new ComboBox { MinWidth = 90 };
        foreach (var seconds in Intervals) interval.Items.Add($"{seconds / 60} Min.");
        interval.SelectedIndex = Math.Max(0, Array.IndexOf(Intervals, settings.RefreshInterval));
        interval.SelectionChanged += (_, _) => settings.RefreshInterval = Intervals[interval.SelectedIndex];
        Field(root, "Abfrageintervall", interval);
        Note(root, "Die Usage-Endpunkte sind hart rate-limitiert. Kürzer als 5 Minuten führt zu Fehlern.");

        Section(root, "Info");
        root.Children.Add(new TextBlock { Text = $"Version {Version}", Margin = new Thickness(0, 4, 0, 0) });
        Note(root, "Automatische Updates gibt es bisher nur in der macOS-Version. Neue Versionen: github.com/mahype/token-stats/releases");

        return root;
    }

    static string Version =>
        Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0] ?? "?";

    static void Section(StackPanel root, string title) => root.Children.Add(new TextBlock
    {
        Text = title,
        FontSize = 14,
        FontWeight = FontWeights.SemiBold,
        Margin = new Thickness(0, root.Children.Count == 0 ? 0 : 20, 0, 6),
    });

    static void Field(StackPanel root, string label, FrameworkElement control)
    {
        var grid = new Grid { Margin = new Thickness(0, 6, 0, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        var text = new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center };
        control.HorizontalAlignment = HorizontalAlignment.Left;
        control.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(control, 1);
        grid.Children.Add(text);
        grid.Children.Add(control);
        root.Children.Add(grid);
    }

    static void Check(StackPanel root, string label, bool value, Action<bool> set)
    {
        var box = new CheckBox { Content = label, IsChecked = value, Margin = new Thickness(0, 6, 0, 0) };
        box.Click += (_, _) => set(box.IsChecked == true);
        root.Children.Add(box);
    }

    static void Note(StackPanel root, string text) => root.Children.Add(new TextBlock
    {
        Text = text,
        FontSize = 12,
        Opacity = 0.7,
        TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(0, 6, 0, 0),
    });
}

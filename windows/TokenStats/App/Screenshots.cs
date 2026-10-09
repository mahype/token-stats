#if DEBUG
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using TokenStats.Model;
using TokenStats.Providers;
using TokenStats.UI;
using TokenStats.Usage;

namespace TokenStats.App;

/// <summary>
/// <c>TOKENSTATS_SCREENSHOTS=&lt;Ordner&gt;</c>: rendert Popup und Tray-Symbol als PNG für die README,
/// dazu das App-Symbol <c>TokenStats.ico</c>. Limits und Verbrauch sind Demo-Werte: keine Abfrage,
/// kein Cache, keine Logs, keine Kontonamen.
/// </summary>
static class Screenshots
{
    public static void Run(string directory)
    {
        Directory.CreateDirectory(directory);
        var now = DateTimeOffset.Now;
        var settings = new AppSettings();
        var store = new UsageStore([new ClaudeProvider(), new CodexProvider(), new AntigravityProvider(), new OllamaProvider()],
                                   settings, cachePath: null);
        var consumption = new ConsumptionStore(settings, ledgerPath: null);
        store.ShowDemo(DemoSnapshots(now));
        consumption.ShowDemo(DemoUsage(now, settings.BillingDay, consumption.Prices));

        foreach (var (suffix, dark) in new[] { ("light", false), ("dark", true) })
        {
            var view = new PopupView(store, consumption, settings, () => { }) { Palette = new Palette(dark), Now = () => now };
            string File(string name) => Path.Combine(directory, $"{name}-{suffix}.png");

            view.Reset("claude");
            Save(Card(view.Build(), view.Palette), File("limits"));
            view.Reset("codex");
            Save(Card(view.Build(), view.Palette), File("limits-codex"));
            view.Reset("antigravity");
            Save(Card(view.Build(), view.Palette), File("limits-antigravity"));
            view.Reset("ollama");
            Save(Card(view.Build(), view.Palette), File("limits-ollama"));
            view.Reset("claude", PopupPage.Usage);
            Save(Card(view.Build(), view.Palette), File("usage"));
            Save(Tray(DemoSnapshots(now)["claude"].Windows, dark), File("tray"));
        }
        WriteIcon(Path.Combine(directory, "TokenStats.ico"));
    }

    /// <summary>Popup-Rahmen nachgebildet: Karte mit runden Ecken, ohne Schatten.</summary>
    static FrameworkElement Card(FrameworkElement content, Palette palette)
    {
        var inner = new Border { Child = content, Clip = null };
        var card = new Border
        {
            CornerRadius = new CornerRadius(8), BorderThickness = new Thickness(1),
            Background = palette.Background, BorderBrush = palette.Separator, Child = inner,
        };
        card.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        card.Arrange(new Rect(card.DesiredSize));
        inner.Clip = new RectangleGeometry(new Rect(inner.RenderSize), 7, 7);
        card.UpdateLayout();
        return card;
    }

    /// <summary>Die drei Anzeige-Modi nebeneinander, in einem Stück Taskleiste.</summary>
    static FrameworkElement Tray(IReadOnlyList<LimitWindow> claude, bool dark)
    {
        var palette = new Palette(dark);
        var row = Ui.Row(22);
        foreach (var mode in MenuBarModes.All)
        {
            var icon = StatusIcon.Render(new StatusIcon.Input(
                mode, Severity.Warn, claude[1].Percent, claude.Take(2).Select(w => w.Percent).ToList(),
                Colored: true, Paused: false, TaskbarDark: dark), 32);
            var image = new Image { Source = icon, Width = 16, Height = 16 };
            RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
            var tile = new Border
            {
                Width = 40, Height = 32, CornerRadius = new CornerRadius(4),
                Background = Palette.Solid(dark ? 0x1C1C1C : 0xEEEEEE), Child = image,
                HorizontalAlignment = HorizontalAlignment.Center,
            };
            var label = Ui.Text(mode.Label(), 11, palette.Secondary);
            label.HorizontalAlignment = HorizontalAlignment.Center;
            Ui.Add(row, Ui.Column(8, tile, label), 22);
        }
        row.Margin = new Thickness(20, 14, 20, 14);
        return Card(row, palette);
    }

    /// <summary>Zeichnet in 2× – scharf auch in der halb breiten README-Tabelle.</summary>
    static void Save(FrameworkElement element, string path)
    {
        const double scale = 2;
        var size = element.RenderSize;
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(size.Width * scale), (int)Math.Ceiling(size.Height * scale),
                                            96 * scale, 96 * scale, PixelFormats.Pbgra32);
        bitmap.Render(element);
        WritePng(bitmap, path);
        Console.WriteLine(Path.GetFileName(path));
    }

    static void WritePng(BitmapSource bitmap, string path)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path);
        encoder.Save(stream);
    }

    /// <summary>App-Symbol: weißer Roboter auf blauem Grund, als ICO mit PNG-Bildern.</summary>
    static void WriteIcon(string path)
    {
        int[] sizes = [16, 24, 32, 48, 256];
        var images = sizes.Select(size =>
        {
            var visual = new DrawingVisual();
            using (var context = visual.RenderOpen())
            {
                var radius = size * 0.22;
                context.DrawRoundedRectangle(Palette.Solid(0x005FB8), null, new Rect(0, 0, size, size), radius, radius);
                RobotGlyph.Draw(context, new Rect(size * 0.12, size * 0.1, size * 0.76, size * 0.76), Brushes.White, minLine: 1.2);
            }
            var bitmap = new RenderTargetBitmap(size, size, 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(visual);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using var stream = new MemoryStream();
            encoder.Save(stream);
            return stream.ToArray();
        }).ToList();

        using var writer = new BinaryWriter(File.Create(path));
        writer.Write((short)0);
        writer.Write((short)1);
        writer.Write((short)sizes.Length);
        var offset = 6 + 16 * sizes.Length;
        for (var index = 0; index < sizes.Length; index++)
        {
            writer.Write((byte)(sizes[index] >= 256 ? 0 : sizes[index]));
            writer.Write((byte)(sizes[index] >= 256 ? 0 : sizes[index]));
            writer.Write((byte)0);
            writer.Write((byte)0);
            writer.Write((short)1);
            writer.Write((short)32);
            writer.Write(images[index].Length);
            writer.Write(offset);
            offset += images[index].Length;
        }
        foreach (var image in images) writer.Write(image);
    }

    // Demo-Werte

    /// <summary>Ein Stand, der alle Zustände zeigt: grün, gelb, Pace vorgegriffen, ungenutzt und im Takt.</summary>
    public static Dictionary<string, ProviderSnapshot> DemoSnapshots(DateTimeOffset now)
    {
        const double hour = 3600;
        const double week = 7 * 24 * hour;
        var weekReset = now.AddSeconds(2.6 * 24 * hour);
        return new()
        {
            ["claude"] = new ProviderSnapshot
            {
                Account = new AccountInfo("Demo", "Max 20×"),
                Windows =
                [
                    new() { Id = "session", Name = "Session", ScopeNote = "5 h", Percent = 0.42, ResetsAt = now.AddSeconds(2.2 * hour), WindowLength = 5 * hour },
                    new() { Id = "week", Name = "Woche", ScopeNote = "7 d, alle Modelle", Percent = 0.82, ResetsAt = weekReset, WindowLength = week },
                    new() { Id = "model-opus", Name = "Opus", ScopeNote = "Wochenlimit", Percent = 0.64, ResetsAt = weekReset, WindowLength = week },
                ],
                Extras = [new ExtraValue("extra", "Extra 12,40 $ / 50,00 $")],
                FetchedAt = now.AddSeconds(-60),
            },
            ["codex"] = new ProviderSnapshot
            {
                Account = new AccountInfo("Demo", "Pro"),
                Windows =
                [
                    new() { Id = "primary", Name = "Woche", ScopeNote = "7 d", Percent = 0.37, ResetsAt = now.AddSeconds(4.1 * 24 * hour), WindowLength = week },
                    new() { Id = "review", Name = "Code-Review", ScopeNote = "7 d", Percent = 0.08, ResetsAt = now.AddSeconds(4.1 * 24 * hour), WindowLength = week },
                ],
                Extras = [new ExtraValue("credits", "Credits unbegrenzt")],
                FetchedAt = now.AddSeconds(-60),
            },
            ["antigravity"] = new ProviderSnapshot
            {
                Account = new AccountInfo("Demo", "Google AI Plus"),
                Windows =
                [
                    new() { Id = "gemini-weekly", Name = "Gemini", ScopeNote = "Wochenlimit", Percent = 0.35, ResetsAt = now.AddSeconds(5.3 * 24 * hour), WindowLength = week },
                    new() { Id = "3p-weekly", Name = "Claude & GPT", ScopeNote = "Wochenlimit", Percent = 0.12, ResetsAt = now.AddSeconds(5.3 * 24 * hour), WindowLength = week },
                ],
                FetchedAt = now.AddSeconds(-60),
            },
            ["ollama"] = new ProviderSnapshot
            {
                Account = new AccountInfo("Demo", "Pro"),
                Windows =
                [
                    new() { Id = "session", Name = "Session", ScopeNote = "5 h", Percent = 0.18 },
                    new() { Id = "weekly", Name = "Woche", ScopeNote = "7 d", Percent = 0.41 },
                ],
                Extras = [new ExtraValue("requests-glm-5.3", "glm-5.3 · 312 Anfragen"), new ExtraValue("requests-kimi-k2.6", "kimi-k2.6 · 48 Anfragen")],
                FetchedAt = now.AddSeconds(-60),
            },
        };
    }

    /// <summary>30 Tage Verbrauch mit Wochenrhythmus; Cache-Anteil wie bei Claude Code üblich um 80 %.</summary>
    public static Dictionary<string, Dictionary<UsagePeriod, UsageSummary>> DemoUsage(DateTimeOffset now, int billingDay, PriceTable prices)
    {
        // Tagesfaktoren, heute zuletzt; die Nullen sind freie Tage.
        double[] pattern = [0.9, 1.2, 0.7, 1.4, 0.3, 0, 0.5, 1.1, 1.3, 0.8, 1.6, 0.9, 0.2, 0,
                            1.0, 0.6, 1.5, 1.2, 0.7, 0.4, 0.1, 1.3, 0.9, 1.1, 1.8, 1.0, 0, 0.6, 1.4, 0.8];
        var models = new Dictionary<string, (string Model, double Share, TokenCounts PerDay)[]>
        {
            ["claude"] =
            [
                ("claude-opus-5-5", 0.7, new TokenCounts(9_000, 310_000, 1_900_000, 600_000, 38_000_000)),
                ("claude-sonnet-5", 0.3, new TokenCounts(14_000, 240_000, 1_400_000, 0, 21_000_000)),
            ],
            ["codex"] = [("gpt-5.6-sol", 1, new TokenCounts(Input: 1_100_000, Output: 180_000, CacheRead: 9_500_000))],
        };
        var today = DateOnly.FromDateTime(now.LocalDateTime);
        static TokenCounts Scaled(TokenCounts counts, double factor)
        {
            long S(long value) => (long)(value * factor);
            return new TokenCounts(S(counts.Input), S(counts.Output), S(counts.CacheWrite5m), S(counts.CacheWrite1h), S(counts.CacheRead));
        }

        return models.ToDictionary(pair => pair.Key, pair =>
        {
            var rows = pattern.SelectMany((factor, index) =>
            {
                var day = UsageSummary.Key(today.AddDays(index - (pattern.Length - 1)));
                return pair.Value.Select(line => new UsageLedger.Row(day, line.Model, Scaled(line.PerDay, factor * line.Share * 2)));
            }).ToList();
            return UsagePeriods.All.ToDictionary(period => period, period =>
            {
                var (from, through) = period.Range(today, billingDay);
                string first = UsageSummary.Key(from), last = UsageSummary.Key(through);
                var inRange = rows.Where(row => string.CompareOrdinal(row.Day, first) >= 0 && string.CompareOrdinal(row.Day, last) <= 0);
                return UsageSummary.Build(inRange, from, through, prices);
            });
        });
    }
}
#endif

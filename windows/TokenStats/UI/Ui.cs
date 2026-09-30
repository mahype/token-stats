using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace TokenStats.UI;

/// <summary>Kleine Bausteine, damit sich das Popup im Code so knapp liest wie die SwiftUI-Views.</summary>
static class Ui
{
    public static readonly FontFamily Font = new("Segoe UI Variable Text, Segoe UI");
    public static readonly FontFamily Icons = new("Segoe Fluent Icons, Segoe MDL2 Assets");

    public static TextBlock Text(string text, double size, Brush brush, FontWeight? weight = null) => new()
    {
        Text = text,
        FontFamily = Font,
        FontSize = size,
        FontWeight = weight ?? FontWeights.Normal,
        Foreground = brush,
        TextTrimming = TextTrimming.CharacterEllipsis,
    };

    public static TextBlock Wrapped(string text, double size, Brush brush)
    {
        var block = Text(text, size, brush);
        block.TextWrapping = TextWrapping.Wrap;
        block.TextTrimming = TextTrimming.None;
        return block;
    }

    public static TextBlock Icon(string glyph, double size, Brush brush) => new()
    {
        Text = glyph,
        FontFamily = Icons,
        FontSize = size,
        Foreground = brush,
        VerticalAlignment = VerticalAlignment.Center,
    };

    public static StackPanel Row(double spacing, params UIElement[] children) => Stack(Orientation.Horizontal, spacing, children);

    public static StackPanel Column(double spacing, params UIElement[] children) => Stack(Orientation.Vertical, spacing, children);

    static StackPanel Stack(Orientation orientation, double spacing, UIElement[] children)
    {
        var panel = new StackPanel { Orientation = orientation };
        foreach (var child in children) Add(panel, child, spacing);
        return panel;
    }

    /// <summary>Hängt ein Element mit Abstand zum vorigen an (StackPanel kennt kein Spacing).</summary>
    public static void Add(StackPanel panel, UIElement child, double spacing)
    {
        if (panel.Children.Count > 0 && child is FrameworkElement element)
        {
            var margin = element.Margin;
            element.Margin = panel.Orientation == Orientation.Horizontal
                ? margin with { Left = margin.Left + spacing }
                : margin with { Top = margin.Top + spacing };
        }
        panel.Children.Add(child);
    }

    /// <summary>Links und rechts ausgerichtet in einer Zeile, wie HStack mit Spacer.</summary>
    public static Grid Spread(UIElement left, UIElement? right, VerticalAlignment alignment = VerticalAlignment.Center)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        if (left is FrameworkElement l) l.VerticalAlignment = alignment;
        grid.Children.Add(left);
        if (right is not null)
        {
            if (right is FrameworkElement r)
            {
                r.VerticalAlignment = alignment;
                r.Margin = r.Margin with { Left = r.Margin.Left + 8 };
            }
            Grid.SetColumn(right, 1);
            grid.Children.Add(right);
        }
        return grid;
    }

    public static Border Divider(Brush brush) => new() { Height = 1, Background = brush, SnapsToDevicePixels = true };

    /// <summary>Klickbare Fläche ohne Button-Chrome, wie <c>.buttonStyle(.plain)</c>.</summary>
    public static Border Clickable(UIElement content, Action action, string? tooltip = null)
    {
        var border = new Border { Child = content, Background = Brushes.Transparent, Cursor = Cursors.Hand, ToolTip = tooltip };
        border.MouseLeftButtonUp += (_, e) =>
        {
            e.Handled = true;
            action();
        };
        return border;
    }
}

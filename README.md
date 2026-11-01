# CoffeeIFY

CoffeeIFY is a customizable Roblox Luau UI library with a warm, paper-inspired visual identity. Its signature and default appearance is the **Paper** theme. It includes draggable and resizable windows, category pages, standard controls, optional alternate themes, page transitions, window animations, optional key gating, saved configuration, notifications, and an opt-in extension system.

> **Compatibility note:** This build uses Roblox services and some executor-provided functions. It is not a standalone Roblox Studio ModuleScript as written. See [Requirements and compatibility](#requirements-and-compatibility) before integrating it.

---

## Contents

- [Features](#features)
- [Quick start](#quick-start)
- [Creating categories and controls](#creating-categories-and-controls)
- [Control reference](#control-reference)
- [Reusable layout components](#reusable-layout-components)
- [Window API](#window-api)
- [Library API](#library-api)
- [Configuration reference](#configuration-reference)
- [Themes, colors, and gradients](#themes-colors-and-gradients)
- [Animations and interaction](#animations-and-interaction)
- [Extensions](#extensions)
- [Flags and saved configuration](#flags-and-saved-configuration)
- [Icons and assets](#icons-and-assets)
- [Sound behavior](#sound-behavior)
- [Requirements and compatibility](#requirements-and-compatibility)
- [Changelog](#changelog)
- [Credits](#credits)

---

## Features

- Draggable, resizable window with a mobile toggle button.
- Single-column and balanced two-column category layouts.
- Responsive fallback from two columns to one column on narrow viewports.
- Built-in `Hello` page containing the profile header, changelog, and credits.
- Built-in `Settings` page, initialized when the window is created.
- Ten standard controls: label, button, text box, number text box, search bar, toggle, slider, color picker, dropdown, and multi-dropdown.
- Eight reusable layout helpers for sections, dividers, spacers, paragraphs, badges, progress bars, action cards, and custom frames.
- Theme presets, custom theme colors, optional gradients, font selection, font scaling, UI scaling, and background images.
- Separate page-transition and window open/close animation systems.
- Optional draggable notifications with animated text and accent effects.
- Optional key system with an internal `AUTH` page.
- Optional extension registration and per-window extension activation.
- Flag values and selected UI settings can be saved when the required file functions are available.
- A singleton guard removes a previous copy of the managed UI before creating another.

---

## Quick start

Place the library at a raw GitHub URL or another location that your environment can retrieve. Replace the placeholder URL below with the raw URL of **your hosted copy**.

```lua
local Library = loadstring(game:HttpGet("YOUR_RAW_GITHUB_URL"))()

local Window = Library:CreateWindow("CoffeeIFY", {
    Theme = "Paper",
    ToggleKey = Enum.KeyCode.RightShift,
    ShowIntro = false,
    layout = {
        ify = "2",
        Gap = 14,
        Responsive = true,
    },
})

local MainTab = Window:CreateCategory("Main", "lucide-house")

MainTab:CreateSection("Main controls", "A simple example category.")

MainTab:CreateButton("Run action", "lucide-play", function()
    print("Button pressed")
end)

MainTab:CreateToggle("Enabled", "lucide-power", true, "EnabledFlag", function(value)
    print("Enabled:", value)
end)

MainTab:CreateSlider("Volume", "lucide-volume-2", 0, 100, 50, "VolumeFlag", function(value)
    print("Volume:", value)
end)
```

`CreateWindow` returns the window object. `CreateCategory` returns four values:

```lua
local Tab, TabPage, TabButton, ColumnOneParent = Window:CreateCategory(
    "Main",
    "lucide-house",
    false
)
```

- `Tab` is the category control API. Use it to create controls.
- `TabPage` is the category's scrolling page `Instance`.
- `TabButton` is the category's sidebar button `Instance`.
- `ColumnOneParent` is the stable content parent for content that must remain in column 1. In single-column mode, it is the page itself.

The last three values are optional; capture only the first value when you do not need them.

---

## Creating categories and controls

Create as many categories as your window needs. Category names are converted to uppercase for the sidebar and page heading.

```lua
local PlayerTab = Window:CreateCategory("Player", "lucide-user")
local VisualTab = Window:CreateCategory("Visuals", "lucide-eye")
local MiscTab = Window:CreateCategory("Misc", "lucide-box")
```

The third argument controls the initial sidebar visibility:

```lua
local HiddenTab, HiddenPage, HiddenButton = Window:CreateCategory(
    "Extra",
    "lucide-sparkles",
    true
)

-- Show the sidebar button later.
HiddenButton.Visible = true
```

The first visible category is selected automatically unless the key system is locking the interface. Settings and Hello are created internally by the library; they do not need to be recreated.

### Clearing a category

```lua
PlayerTab:ClearItems()
```

`ClearItems()` removes controls and generated content from the category while preserving its layout containers and heading. You can then add new controls to the same category object.

---

## Control reference

All control constructors are methods of the category object returned by `CreateCategory`.

### `CreateLabel`

```lua
Tab:CreateLabel(Text, IconName, TextColor)
```

Creates a text label with an optional icon. `TextColor` is an optional `Color3`. The second argument may be a `Color3` when no icon is needed.

```lua
Tab:CreateLabel("Player information", "lucide-user")
Tab:CreateLabel("Custom colored text", Color3.fromRGB(120, 200, 255))
```

Returns the created text label `Instance`.

### `CreateButton`

```lua
Tab:CreateButton(ButtonText, IconName, TextColor, Callback)
```

Creates a clickable row and runs `Callback` when pressed. The icon and text color are optional. A callback can be passed directly as the second argument.

```lua
Tab:CreateButton("Print message", "lucide-terminal", function()
    print("Hello")
end)

Tab:CreateButton("No icon", function()
    print("Clicked")
end)
```

Returns a small controller with `SetText(newText)`.

```lua
local Button = Tab:CreateButton("Start", function()
    print("Started")
end)

Button.SetText("Run again")
```

### `CreateTextbox`

```lua
Tab:CreateTextbox(TextboxText, IconName, Placeholder, Flag, Callback)
```

Creates a text input. The callback runs when the text box loses focus. If a `Flag` is supplied, the current text is included in saved flag data.

```lua
local NameInput = Tab:CreateTextbox(
    "Display name",
    "lucide-user",
    "Type a name...",
    "DisplayName",
    function(text)
        print("Entered:", text)
    end
)

print(NameInput.Get())
NameInput.Set("Guest")
```

Returned members:

- `Get()` returns the current string.
- `Set(value)` changes the text. It does not invoke the callback.
- `TextBox` exposes the underlying Roblox `TextBox` instance.

The `Flag` argument may be omitted by passing the callback in its place:

```lua
Tab:CreateTextbox("Search term", "lucide-search", "Search...", function(text)
    print(text)
end)
```

### `CreateNumberTextbox`

```lua
Tab:CreateNumberTextbox(LabelText, IconName, DefaultNumber, Flag, Callback)
```

Creates a text input intended for numeric values. Its callback receives `tonumber(text)`, which can be `nil` when the input is not numeric.

```lua
local AmountInput = Tab:CreateNumberTextbox(
    "Amount",
    "lucide-hash",
    25,
    "AmountFlag",
    function(number)
        print("Amount:", number)
    end
)

print(AmountInput.Get())
AmountInput.Set(40)
```

Returned members:

- `Get()` returns the numeric value or `nil`.
- `GetText()` returns the raw text.
- `Set(value)` accepts a numeric value, updates the text, and invokes the callback. It returns `false` for invalid numeric input and `true` on success.
- `TextBox` exposes the underlying Roblox `TextBox` instance.

### `CreateSearchBar`

```lua
Tab:CreateSearchBar(Placeholder, IconName, Callback)
```

Creates a search input. The callback runs whenever the text changes.

```lua
local Search = Tab:CreateSearchBar("Search players...", function(query)
    print("Query:", query)
end)

Search.Set("Builder")
print(Search.Get())
```

The icon is optional and defaults to `lucide-search`. Returned members are `Get()`, `Set(value)`, and `TextBox`.

### `CreateToggle`

```lua
Tab:CreateToggle(ToggleText, IconName, DefaultState, Flag, Callback)
```

Creates an ON/OFF toggle. The callback receives a boolean. Saved flag data takes precedence over `DefaultState` when a matching saved flag exists. The implementation also invokes the callback once during construction with the initial/restored state.

```lua
local EnabledToggle = Tab:CreateToggle(
    "Enabled",
    "lucide-power",
    false,
    "FeatureEnabled",
    function(enabled)
        print("Feature enabled:", enabled)
    end
)

print(EnabledToggle.Get())
EnabledToggle.Set(true)
```

The icon can be omitted by using the shorter form:

```lua
Tab:CreateToggle("Enabled", false, function(enabled)
    print(enabled)
end)
```

Returned members are `Get()` and `Set(boolean)`. Calling `Set` invokes the callback.

### `CreateSlider`

```lua
Tab:CreateSlider(SliderText, IconName, Min, Max, Default, Flag, Callback)
```

Creates an integer slider. The default is clamped to the supplied range. The callback receives the selected value.

```lua
local SpeedSlider = Tab:CreateSlider(
    "Speed",
    "lucide-gauge",
    0,
    100,
    25,
    "SpeedFlag",
    function(value)
        print("Speed:", value)
    end
)

print(SpeedSlider.Get())
SpeedSlider.Set(60)
```

The icon can be omitted:

```lua
Tab:CreateSlider("Opacity", 0, 100, 75, function(value)
    print(value)
end)
```

Returned members are `Get()` and `Set(value)`. `Set` returns `false` for invalid input and `true` when the value is accepted. Values are rounded to the nearest integer and clamped to the slider range.

### `CreateColorPicker`

```lua
Tab:CreateColorPicker(PickerText, IconName, DefaultColor, Flag, Callback)
```

Creates an expandable hue and saturation/value color picker. The callback receives a Roblox `Color3`.

```lua
local AccentPicker = Tab:CreateColorPicker(
    "Accent color",
    "lucide-palette",
    Color3.fromRGB(120, 90, 220),
    "AccentFlag",
    function(color)
        print("New color:", color)
    end
)

print(AccentPicker.GetHex())
AccentPicker.Set(Color3.fromRGB(255, 120, 80))
```

Returned members are `Get()`, `Set(color)`, `GetHex()`, and `Container`. `Set` accepts only a `Color3` and returns a boolean.

### `CreateDropdown`

```lua
Tab:CreateDropdown(DropdownText, IconName, Options, Default, Flag, Callback)
```

Creates a searchable single-selection dropdown. The callback receives the selected option.

```lua
local ModeDropdown = Tab:CreateDropdown(
    "Mode",
    "lucide-list",
    { "Balanced", "Fast", "Precise" },
    "Balanced",
    "ModeFlag",
    function(selected)
        print("Mode:", selected)
    end
)

print(ModeDropdown:GetValue())
ModeDropdown:SetValue("Fast")
```

The icon can be omitted by passing the options table as the second argument. Returned members:

- `Refresh(options)` rebuilds the displayed choices while retaining valid current selection.
- `SetOptions(options)` replaces the choices.
- `GetValue()` returns the selected value.
- `SetValue(value)` selects a value and invokes the callback.

### `CreateMultiDropdown`

```lua
Tab:CreateMultiDropdown(DropdownText, IconName, Options, DefaultSelected, Flag, Callback)
```

Creates a searchable multi-selection dropdown with `Select All` and `Clear All` actions. The callback receives an array of selected options.

```lua
local FeatureDropdown = Tab:CreateMultiDropdown(
    "Features",
    "lucide-list-checks",
    { "Particles", "Shadows", "Bloom", "Reflections" },
    { "Particles", "Bloom" },
    "SelectedFeatures",
    function(selected)
        print("Selected:", table.concat(selected, ", "))
    end
)

for _, item in ipairs(FeatureDropdown:GetSelected()) do
    print(item)
end

FeatureDropdown:SetSelected({ "Shadows", "Bloom" })
```

The icon can be omitted by passing the options table as the second argument. Returned members:

- `Refresh(options)` rebuilds choices and removes selections that are no longer valid.
- `SetOptions(options)` replaces the choices and clears the current multi-selection before rebuilding.
- `GetSelected()` returns the selected array.
- `SetSelected(values)` applies valid values and invokes the callback.

---

## Reusable layout components

These helpers are useful for extension panels and information pages. They are methods of a category object.

### `CreateSection`

```lua
local Section = Tab:CreateSection("Section title", "Optional supporting text")
Section:SetTitle("Updated title")
Section:SetSubtitle("Updated supporting text")
Section:Destroy()
```

Creates a section heading with an optional subtitle and divider. Returns a controller with `Instance`, `SetTitle`, `SetSubtitle`, and `Destroy`.

### `CreateDivider`

```lua
local Divider = Tab:CreateDivider("Advanced")
Divider:SetLabel("General")
Divider:Destroy()
```

Creates a thin divider. The optional label is displayed in uppercase. Returns `Instance`, `SetLabel`, and `Destroy`.

### `CreateSpacer`

```lua
local Spacer = Tab:CreateSpacer(16)
Spacer:SetHeight(24)
Spacer:Destroy()
```

Creates vertical space. Height is clamped to `2`–`80` pixels. Returns `Instance`, `SetHeight`, and `Destroy`.

### `CreateParagraph`

```lua
local Paragraph = Tab:CreateParagraph(
    "About this feature",
    "A longer description that wraps and adjusts its height to the available width."
)

Paragraph:SetTitle("Updated title")
Paragraph:SetText("Updated description")
Paragraph:Destroy()
```

Creates a themed text panel with automatic height measurement. Returns `Instance`, `SetTitle`, `SetText`, and `Destroy`.

### `CreateBadge`

```lua
local Status = Tab:CreateBadge("Connection", "ONLINE", Color3.fromRGB(80, 190, 120))
Status:SetLabel("Server status")
Status:SetText("READY")
Status:SetColor(Color3.fromRGB(100, 170, 255))
Status:Destroy()
```

Creates a label with a status pill. Returns `Instance`, `SetLabel`, `SetText`, `SetColor`, and `Destroy`.

### `CreateProgressBar`

```lua
local Progress = Tab:CreateProgressBar("Download", 35, 100, Color3.fromRGB(90, 170, 255))
Progress:SetValue(60)
Progress:SetMax(150)
Progress:SetTitle("Updated progress")
Progress:SetColor(Color3.fromRGB(120, 220, 150))
print(Progress:GetValue())
Progress:Destroy()
```

Creates a progress bar. The value is clamped between `0` and the maximum. Returns `Instance`, `SetValue`, `GetValue`, `SetMax`, `SetTitle`, `SetColor`, and `Destroy`.

### `CreateActionCard`

```lua
local Action = Tab:CreateActionCard(
    "Refresh data",
    "Fetch the latest local data.",
    "REFRESH",
    function()
        print("Refresh requested")
    end
)

Action:SetTitle("Reload data")
Action:SetDescription("Run the reload callback.")
Action:SetButtonText("RELOAD")
Action:SetEnabled(false)
Action:SetEnabled(true)
Action:SetCallback(function()
    print("Reloaded")
end)
Action:Destroy()
```

Creates a compact card with a callback button. Callback errors are caught and reported through a notification. Returns `Instance`, `SetTitle`, `SetDescription`, `SetButtonText`, `SetCallback`, `SetEnabled`, and `Destroy`.

### `CreateCustomFrame`

```lua
local CustomFrame = Tab:CreateCustomFrame("MyFrame", 100, {
    ThemeColor = "Row",
    Glass = true,
    Gradient = true,
    ClipsDescendants = true,
})

local CustomText = Instance.new("TextLabel")
CustomText.BackgroundTransparency = 1
CustomText.Size = UDim2.fromScale(1, 1)
CustomText.Text = "Custom Roblox UI content"
CustomText.Parent = CustomFrame
```

Creates and returns a Roblox `Frame` instance. Use it as a parent for your own Roblox UI objects.

Supported `Options` fields:

| Option | Type | Behavior |
|---|---|---|
| `BackgroundTransparency` | number | Sets transparency, clamped to `0`–`1`. |
| `BackgroundColor3` | `Color3` | Uses this explicit background color. |
| `ThemeColor` | string | Uses a valid theme token when no explicit `BackgroundColor3` is supplied. |
| `Glass` | boolean | Enables the library's shared glass-transparency behavior. |
| `Gradient` | boolean | Adds the library's optional gradient. |
| `ClipsDescendants` | boolean | Clips child content when set to `true`. |

The height is clamped to `24`–`500` pixels. When `BackgroundColor3` is omitted, the default theme token is `Row`.

---

## Window API

The object returned by `Library:CreateWindow(...)` exposes the following methods and members.

| Method or member | Purpose |
|---|---|
| `CreateCategory(name, icon, hidden)` | Creates a category and returns the category API, page, sidebar button, and column-one parent. |
| `CreateExtensionCategory(name, icon, hidden)` | Alias for `CreateCategory`. |
| `OpenSettings()` | Opens the built-in Settings page. |
| `CloseSettings()` | Closes Settings and returns to the previous visible page. |
| `ToggleSettings()` | Opens or closes Settings. |
| `Show()` | Opens the window. |
| `Hide()` | Hides the window. |
| `ToggleVisibility()` | Toggles the window visibility. |
| `Destroy()` | Disconnects tracked window connections and destroys the ScreenGui. |
| `Notify(text, duration, opts)` | Displays a notification. |
| `SetThemeColor(token, color)` | Sets a supported theme token to a `Color3`. |
| `GetThemeColor(token)` | Returns the current value of a theme token. |
| `GetTheme()` | Returns a shallow copy of the current theme table. |
| `GetLayoutMode()` | Returns the layout mode string, `"1"` or `"2"`. |
| `GetActiveColumnCount()` | Returns the active column count. |
| `ApplyTeamColor(instance, property)` | Binds an instance property to the `Team` theme token. |
| `UpdateTeamColor(color)` | Updates the `Team` theme token with a theme transition. |
| `GetTeamColor()` | Returns the current `Team` color. |
| `UpdateBackgroundImage(id)` | Changes the background image asset string. |
| `UpdateBackgroundImageTransparency(value)` | Changes background image transparency. |
| `UpdateBackgroundImageEnabled(state)` | Enables or disables the background image. |
| `RunExtension(name, ...)` | Runs a registered extension and returns success plus its result or error. |
| `IsAuthenticated()` | Returns the current key-system authentication state. |
| `SetAuthenticated(state)` | Sets the authentication state. |
| `EnableKeySystem(key, note)` | Enables key gating for categories. |
| `DisableKeySystem()` | Disables key gating. |
| `GetFlag(name)` | Reads a registered flag value. See the flag note below. |
| `SetFlag(name, value)` | Updates a registered flag value and saves configuration. |
| `SaveConfiguration()` | Writes the current window and flag configuration when file APIs are available. |
| `SetToggleKey(keyCode)` | Changes the keyboard visibility toggle key. |
| `SetMobileStyle(name)` | Changes the mobile toggle button style. |
| `SetDragDelay(milliseconds)` | Sets the hold delay before dragging. |
| `GetDragDelay()` | Returns the drag delay in milliseconds. |
| `SetGradientEffects(enabled)` | Enables or disables optional gradients. |
| `GetGradientEffects()` | Returns whether gradient effects are enabled. |
| `SetGradientDirection(direction)` | Changes gradient direction. |
| `GetGradientDirection()` | Returns the current gradient direction. |
| `Flags` | Table containing registered flag records. |
| `Layout` | Table describing the selected layout and active column count. |

Example:

```lua
Window:Notify("Settings saved", 3)
Window:SetThemeColor("Accent", Color3.fromRGB(110, 90, 220))
Window:SetGradientEffects(true)
Window:SetGradientDirection("Horizontal")
Window:SetDragDelay(180)

print(Window:GetLayoutMode())
print(Window:GetActiveColumnCount())
```

### Theme tokens

The supported theme tokens are:

```lua
local ThemeTokens = {
    "Paper",
    "Row",
    "Input",
    "Accent",
    "Ink",
    "Cream",
    "Line",
    "Team",
}
```

`SetThemeColor` returns `false` when the token is not supported or the color is not a `Color3`; otherwise it returns `true` and applies the update through the theme-transition system.

### Notification options

You can pass either a text string or an options table.

```lua
Window:Notify("Operation complete", 3)

Window:Notify({
    Title = "COMPLETE",
    Description = "Your settings have been applied.",
    Duration = 4,
})
```

Supported table fields are `Title`, `Text`, `Description`, `Duration`, and `Time`. The plain-text form accepts `text`, `duration`, and an optional options table. Notifications are draggable and stack along the lower-left side of the screen until moved.

---

## Library API

The `Library` table is returned by the source file. Its public members include:

| Member | Purpose |
|---|---|
| `CreateWindow(name, config)` | Creates a window and returns its window API. |
| `SetLayoutMode(value)` | Sets the default layout used by future windows unless overridden by window config. |
| `layout` | Default layout table. The `ify` field accepts `"1"` or `"2"`. |
| `Presets` | Table containing the built-in theme preset data. |
| `Icons` | Icon lookup table loaded from the configured remote icon source, if available. |
| `Extensions` | Registry of extension callbacks. |
| `RegisterExtension(name, callback)` | Registers or replaces an extension. |
| `UnregisterExtension(name)` | Removes a registered extension. |
| `GetExtension(name)` | Returns a registered extension callback or `nil`. |
| `SoundEnabled` | Global sound enabled state. Defaults to `true`. |
| `SoundVolume` | Global sound volume. Defaults to `1`. |
| `SetSoundEnabled(state)` | Enables sound only when `state == true`. |
| `SetSoundVolume(value)` | Sets sound volume in the `0`–`1` range. |

`Library:SetLayoutMode("2")` selects two columns for subsequently created windows. Any value other than `"2"` selects one column. A window's `layout` or `Layout` config takes priority over the library default.

```lua
Library:SetLayoutMode("2")

local Window = Library:CreateWindow("Two Column UI", {
    layout = {
        ify = "2",
        Gap = 16,
        Responsive = true,
    },
})
```

`SetSoundVolume` returns `false` for invalid input and `true` when the value is accepted. The value is clamped to `0`–`1`.

---

## Configuration reference

Pass configuration as the second argument to `Library:CreateWindow(windowName, config)`.

| Field | Type | Default | Description |
|---|---|---|---|
| `Theme` | string | `"Paper"` | Initial preset name. |
| `layout` / `Layout` | table | `Library.layout` | Per-window layout configuration. Lowercase `layout` takes priority when both are tables. |
| `layout.ify` / `layout.Ify` | string | `"1"` | `"1"` for one column; `"2"` for two columns. |
| `layout.Gap` / `layout.gap` | number | `14` | Space between columns, clamped to `6`–`28`. |
| `layout.Responsive` / `layout.responsive` | boolean | `true` | Allows two-column mode to fall back to one column on narrow screens. |
| `BackgroundColor` | `Color3` | Theme preset | Overrides the `Paper` theme token. |
| `ElementColor` | `Color3` | Theme preset | Overrides the `Row` theme token. |
| `ButtonColor` | `Color3` | Theme preset | Also overrides the `Row` theme token. |
| `InputColor` | `Color3` | Theme preset | Overrides the `Input` theme token. |
| `ThemeColor` | `Color3` | Theme preset | Overrides the `Accent` theme token. |
| `CategoryColor` | `Color3` | Theme preset | Also overrides the `Accent` theme token. |
| `TextColor` | `Color3` | Theme preset | Overrides the `Ink` theme token. |
| `TeamColor` | `Color3` | Theme preset | Overrides the `Team` theme token. |
| `ElementTransparency` | number | `0.08` | Shared glass transparency, clamped to `0`–`0.9`. |
| `ToggleKey` | `Enum.KeyCode` or `false` | `Enum.KeyCode.RightShift` | Keyboard visibility toggle. Use `false` to disable the keyboard toggle. |
| `ToggleConfig` | table | `{}` | Mobile toggle appearance. Supports `Text` and `Image`. |
| `ToggleConfig.Text` | string | `"◆"` | Text glyph used by applicable mobile toggle styles. |
| `ToggleConfig.Image` | string | none | Image asset string used instead of the text glyph. |
| `MobileButtonStyle` | string | `"Classic"` | One of `Classic`, `Circle`, `Diamond`, `Pill`, or `Bracket`. |
| `ToggleButtonScale` | number | `100` | Initial mobile toggle size percentage, clamped to `50`–`180`. |
| `OverallScale` | number | `100` | Initial overall window scale percentage, clamped to `70`–`130`. |
| `FontFamily` | string | `"Gotham"` | A valid `Enum.Font` name. |
| `FontScale` | number | `1` | Font scale multiplier, clamped to `0.75`–`1.35`. |
| `Language` | string | `"en"` | Supports `"en"` and `"th"` for the translated Settings labels. `"thai"` is also accepted. |
| `BorderEnabled` | boolean | `true` | Enables the main window border unless explicitly `false`. |
| `BackgroundImage` | string | `""` | Background image asset string. |
| `BackgroundImageTransparency` | number | `0.5` | Background image transparency, clamped to `0`–`1`. |
| `BackgroundImageEnabled` | boolean | Based on whether an image is provided | Explicitly enables or disables the background image. |
| `GradientEffects` | boolean | `false` | Enables gradients initially only when set to `true`. |
| `DragDelayMs` / `DragDelay` | number | `140` | Hold delay before dragging, in milliseconds, clamped to `0`–`600`. `DragDelayMs` takes priority. |
| `DisplayOrder` | number | `999` | `ScreenGui.DisplayOrder`. |
| `Logo` | string | none | Image asset string displayed beside the window title. |
| `ShowIntro` | boolean | `true` | Shows the welcome overlay unless set to `false`. |
| `ShowSettingsTab` | boolean | `true` | Creates the built-in Settings category unless set to `false`. |
| `StartOpen` | boolean | `true` | Opens the window after creation unless set to `false`. |
| `ToggleHint` | boolean | `true` | Shows the keyboard-toggle hint unless set to `false`. |
| `KeySystem` | boolean | `false` | Enables the built-in key gate when exactly `true`. |
| `KeySystemConfig` | table | `{}` | Key settings. Supports `Key` or `ExpectedKey`, plus `Note`. |
| `Extensions` | table | none | Opts into registered or inline extensions. See [Extensions](#extensions). |

Example configuration:

```lua
local Window = Library:CreateWindow("Example", {
    Theme = "Graphite",
    Logo = "rbxassetid://1234567890",
    DisplayOrder = 1000,

    ToggleKey = Enum.KeyCode.RightShift,
    ToggleConfig = {
        Text = "◆",
        -- Image = "rbxassetid://1234567890",
    },
    MobileButtonStyle = "Diamond",
    ToggleButtonScale = 110,
    OverallScale = 100,

    FontFamily = "Gotham",
    FontScale = 1,
    ElementTransparency = 0.08,
    BorderEnabled = true,

    GradientEffects = false,
    DragDelayMs = 140,

    layout = {
        ify = "2",
        Gap = 14,
        Responsive = true,
    },

    ShowIntro = false,
    ShowSettingsTab = true,
    StartOpen = true,
    ToggleHint = true,
})
```

**Saved settings can override initial values.** When a valid saved configuration exists, the library restores window size and position, registered flags, theme colors, and several appearance preferences. To test initial settings without restored preferences, remove or rename the saved `UI_Config.json` file in the executor's file storage.

---

## Themes, colors, and gradients

**Paper is CoffeeIFY's primary theme and the default appearance.** The source loads the Paper palette before applying any optional configuration overrides. When `Theme` is omitted—or an unknown preset name is supplied—the window falls back to Paper. Other themes are optional alternatives; they do not replace Paper as the main CoffeeIFY look.

The built-in preset names are:

```lua
local ThemeNames = {
    "Paper",
    "Gold",
    "Dusk",
    "Sakura",
    "Lavender",
    "Moss",
    "Obsidian",
    "Graphite",
    "Noir",
    "Forest",
    "Olive",
    "Matrix",
    "Twilight",
    "Amethyst",
    "Cyberpunk",
    "Wine",
    "Crimson",
    "Sunset",
    "Ember",
    "Mocha",
    "Halloween",
    "Christmas",
}
```

The default and main preset is `Paper`. You can keep CoffeeIFY in its intended Paper appearance by omitting `Theme` or setting `Theme = "Paper"`. The other preset names—including the optional dark `Obsidian` preset—are alternatives only. Presets can be changed in Settings or selected through the `Theme` field when creating a window.

The default Paper palette is built from these source-defined colors:

| Token | RGB | Purpose in the Paper palette |
|---|---:|---|
| `Paper` | `204, 198, 174` | Main warm beige surface |
| `Row` | `172, 166, 149` | Control and row surfaces |
| `Input` | `226, 220, 198` | Input backgrounds |
| `Accent` | `54, 50, 44` | Primary accent |
| `Ink` | `72, 66, 52` | Main text |
| `Cream` | `252, 248, 220` | Light foreground details |
| `Line` | `158, 152, 129` | Borders and dividers |
| `Team` | `120, 110, 80` | Team/status color |

To explicitly select CoffeeIFY's main theme:

```lua
local Window = Library:CreateWindow("CoffeeIFY", {
    Theme = "Paper",
})
```

The Settings page supports:

- Preset theme selection.
- Optional gradient effects.
- Gradient direction: `Diagonal`, `Horizontal`, or `Vertical`.
- Font family and font scale.
- Overall UI scale.
- Shared element transparency.
- Window border visibility.
- Background image and its transparency.
- Sound volume.

Custom theme updates use `Color3` values:

```lua
Window:SetThemeColor("Accent", Color3.fromRGB(100, 130, 255))

local CurrentAccent = Window:GetThemeColor("Accent")
local CurrentTheme = Window:GetTheme()
```

A gradient direction can be changed with:

```lua
Window:SetGradientDirection("Diagonal")
Window:SetGradientDirection("Horizontal")
Window:SetGradientDirection("Vertical")
```

---

## Animations and interaction

The library has two separate animation settings. They are not interchangeable.

### Page transitions

The Settings page's **Page Transition** dropdown controls the effect used when switching category pages:

| Option | Effect |
|---|---|
| `Pop` | Page scales in from its center with a soft overshoot while content fades in. |
| `Cascade` | Page slides in from the left while rows fade in sequentially. |
| `Glitch` | Page jitters and visible text uses a short scramble effect. |
| `Slide Left` | Page enters from the right and moves left into place while rows fade in. |

### Window open/close animations

The Settings page's **Window** dropdown controls the strip-wipe effect used when showing or hiding the main window:

| Option | Effect |
|---|---|
| `Classic` | Original angled strip wipe. |
| `Shutter` | Straight vertical strips with a centered collapse. |
| `Pinstripe` | Thin vertical strips with a tighter stagger. |
| `Crosscut` | Alternating diagonal strips that cross each other. |

### Dragging and resizing

- Drag the top bar to move the main window.
- Use the resize handle to change the window size.
- The window size is clamped by the implementation to `360`–`900` pixels wide and `240`–`650` pixels tall.
- The hold-to-drag delay is configurable from `0` to `600` milliseconds.
- The mobile toggle button can be dragged and is clamped to the viewport.
- Notification cards can be dragged independently.

### Mobile toggle styles

The supported `MobileButtonStyle` values are:

```lua
local MobileButtonStyles = {
    "Classic",
    "Circle",
    "Diamond",
    "Pill",
    "Bracket",
}
```

The mobile toggle button is shown when touch is available and keyboard input is not available. Desktop keyboard toggling uses `ToggleKey`.

---

## Extensions

Extensions let developers add optional UI without editing the core library. An extension is registered once and explicitly enabled for a window.

### Register an extension

```lua
Library:RegisterExtension("StatusPanel", function(window, library)
    local ExtraTab = window:CreateCategory("Extras", "lucide-sparkles")

    ExtraTab:CreateSection("Status tools", "Optional extension content.")
    ExtraTab:CreateParagraph(
        "About",
        "This page was added by a registered extension."
    )
    ExtraTab:CreateBadge("Extension", "ACTIVE")
end)
```

The callback receives:

1. `window` — the window API returned by `CreateWindow`.
2. `library` — the library table.

### Enable an extension for a window

```lua
local Window = Library:CreateWindow("Extended UI", {
    Extensions = { "StatusPanel" },
})
```

Extensions are opt-in. Registering one does not execute it by itself.

### Run an extension manually

```lua
local success, result = Window:RunExtension("StatusPanel")

if not success then
    warn(result)
end
```

`RunExtension` returns `true, result` on success or `false, errorMessage` when the extension is missing or throws an error.

### Inline extension forms

`Config.Extensions` supports these forms. Each snippet shows the value to place in the `CreateWindow` config table:

```lua
-- A registered extension name.
local ExtensionConfig = {
    Extensions = { "StatusPanel" },
}
```

```lua
-- A direct callback.
local ExtensionConfig = {
    Extensions = {
        function(window, library)
            local Tab = window:CreateCategory("Inline", "lucide-code")
            Tab:CreateLabel("Loaded from an inline callback")
        end,
    },
}
```

```lua
-- A named record with an enabled switch and callback.
local ExtensionConfig = {
    Extensions = {
        {
            Name = "InlinePanel",
            Enabled = true,
            Run = function(window, library)
                local Tab = window:CreateCategory("Inline", "lucide-code")
                Tab:CreateLabel("Inline extension record")
            end,
        },
    },
}
```

```lua
-- A name-to-boolean map for registered extensions.
local ExtensionConfig = {
    Extensions = {
        StatusPanel = true,
    },
}
```

A record may use `Callback` instead of `Run`. Setting `Enabled = false` skips that record.

### Extension registry methods

```lua
local ok, message = Library:RegisterExtension("MyExtension", function(window, library)
    print("Extension loaded")
end)

local callback = Library:GetExtension("MyExtension")
local removed = Library:UnregisterExtension("MyExtension")
```

`RegisterExtension` returns `false` plus an error message when the name or callback is invalid. Registering an existing name replaces its callback. `UnregisterExtension` returns `false` when no matching extension exists.

---

## Flags and saved configuration

Controls that accept a `Flag` argument register their current value in the library's shared flag table. The flag record has this general shape:

```lua
{
    Type = "Toggle",
    Value = true,
}
```

The `Type` depends on the control. Supported flag-backed controls are text boxes, number text boxes, toggles, sliders, color pickers, dropdowns, and multi-dropdowns.

Use unique flag names for controls. A saved flag with the same name can replace the control's supplied default when the window is created.

```lua
local Enabled = Tab:CreateToggle("Enabled", "lucide-power", false, "FeatureEnabled")
local Speed = Tab:CreateSlider("Speed", "lucide-gauge", 0, 100, 25, "Speed")

print(Window:GetFlag("FeatureEnabled"))
Window:SetFlag("Speed", 80)
Window:SaveConfiguration()
```

`Window.Flags` exposes the full flag record table. `GetFlag` is implemented as a truthiness-based lookup, so a stored value of `false` is returned as `nil`; inspect `Window.Flags[name].Value` when you need to distinguish `false` from a missing flag.

`SetFlag` changes the stored flag value and saves it. It does not call the control's setter or callback, so use the control's own `Set` method when you also need to update its visible state.

### Persistence details

The library uses the file name:

```lua
"UI_Config.json"
```

The saved data includes window dimensions and position, registered flag values, and theme/appearance settings. The implementation checks for executor file functions including `writefile`, `readfile`, and `isfile`. If those functions are unavailable, configuration persistence is skipped.

The library does not expose a configuration filename setting or a public save-disable option in this source version.

---

## Icons and assets

Icon arguments are strings. The resolver supports two forms:

1. A key in the remote icon table, commonly formatted like `lucide-house` or `lucide-settings`.
2. A Roblox asset string containing `rbxassetid://`.

```lua
Tab:CreateButton("Open", "lucide-folder-open", function()
    print("Open")
end)

Tab:CreateButton("Custom image", "rbxassetid://1234567890", function()
    print("Custom icon")
end)
```

The source attempts to retrieve the icon table from this URL:

```text
https://github.com/PMLOLHUB/assets-library-/raw/refs/heads/main/Icon
```

The lookup is optional. If the remote icon source cannot be retrieved or compiled, the UI still creates controls, but unavailable icon names use the library's simple geometric marker fallback.

For custom title and mobile toggle images, use the `Logo` and `ToggleConfig.Image` configuration fields respectively. Roblox image assets must be accessible to the client.

---

## Sound behavior

Sound is enabled by default. The source attempts to load the optional Nier sound module from:

```text
https://github.com/PMLOLHUB/assets-library-/raw/refs/heads/main/NierSound.lua
```

It also attempts to download two supplemental MP3 files:

```text
https://github.com/jawolskimanowski-ui/CoffeeIFY-renewed/raw/refs/heads/main/Robotic-female-sound-effect-warning.mp3
https://github.com/jawolskimanowski-ui/CoffeeIFY-renewed/raw/refs/heads/main/Button%20Click%202%20-%20Kaino.mp3
```

The supplemental notification sound is assigned to notification events. The supplemental click sound is assigned to hover, select, and toggle events. Slider, window open, and window close sounds are left to the optional Nier sound module.

The MP3 download path uses file and custom-asset functions when available, including `writefile`, `makefolder`, `isfolder`, `isfile`, and either `getcustomasset` or `getsynasset`. If the required functions or remote files are unavailable, those supplemental sounds may not load.

Control sound globally with:

```lua
Library:SetSoundEnabled(false)
Library:SetSoundEnabled(true)
Library:SetSoundVolume(0.5) -- 50 percent
```

The volume range is `0`–`1`. The Settings page also includes a Sound Volume slider.

---

## Requirements and compatibility

The source uses Roblox services including `Players`, `TweenService`, `TextService`, `UserInputService`, `HttpService`, `SoundService`, `Lighting`, and the current camera. It expects a client context with `Players.LocalPlayer`.

The implementation attempts to use executor functions where present:

| Function | Used for |
|---|---|
| `loadstring` | Compiling the remotely retrieved icon and sound module source. |
| `game:HttpGet` | Retrieving icon/module source and supplemental audio files. |
| `getgenv` / `getfenv` | Looking up executor functions and storing the singleton reference. |
| `gethui` | Preferred parent for the ScreenGui when available. |
| `writefile`, `readfile`, `isfile` | Saving and restoring configuration. |
| `makefolder`, `isfolder` | Creating the optional sound asset folder. |
| `getcustomasset` / `getsynasset` | Converting downloaded sound files into usable asset IDs. |

The UI parent selection tries `gethui`, then `CoreGui`, then the local player's `PlayerGui`. If all parenting attempts fail, window creation raises an error.

### Important limitations

- The supplied file returns a `Library` table, but it is written for an environment that provides the client-side and executor capabilities listed above.
- Remote icon and sound resources are optional dependencies. Their availability is not guaranteed by the library itself.
- File persistence is optional and depends on executor file APIs.
- The key system is a client-side UI gate, not secure server-side authorization. A key embedded in a client-delivered script can be inspected or bypassed by a determined user. Do not use it to protect server authority, private data, or valuable game actions.
- The source does not declare a license. Confirm the original authors' licensing terms before redistributing or incorporating their work.

---

## Changelog

This section summarizes the differences documented in the supplied source header and the visible internal Hello-page changelog.

### Interaction and notifications

- Added delayed hold-to-drag behavior.
- Added independently draggable notification cards.
- Retained the notification rail styling, slide-in/slide-out behavior, typewriter text, and short scramble effect.
- Added configurable drag timing and persisted preferences.

### Themes and gradients

- Added optional theme gradients.
- Added `Diagonal`, `Horizontal`, and `Vertical` gradient directions.
- Added developer-facing theme color getters and setters.
- Kept gradients optional so the flat appearance can remain enabled by default.

### Layout

- Added `layout.ify = "1"` for the original single-column layout.
- Added `layout.ify = "2"` for a balanced two-column layout.
- Added a responsive fallback to one column on narrow viewports when responsive mode is enabled.
- Pinned internal Settings and Hello content to column 1.

### Developer extensions

- Added the extension registry and per-window extension activation.
- Added `CreateSection`, `CreateDivider`, `CreateSpacer`, `CreateParagraph`, `CreateBadge`, `CreateProgressBar`, `CreateActionCard`, and `CreateCustomFrame`.
- Added update and destroy methods to the reusable helper components.

### Settings and internal pages

- Settings is created synchronously so the gear button is available when `CreateWindow` returns.
- Settings rebuilding preserves the column containers.
- The internal Hello page is created synchronously.
- The Hello profile header, changelog, and credits are placed directly in its first-column content area.

### Build note

This CoffeeIFY build includes the synchronous Settings initialization, the internal Hello page changelog, and the optional two-column layout described by the source header.

---

## Credits

The supplied source credits:

- Visual design and most of the core script: Nier
- Additional UI work: jawolskimanowski
- Feedback contact: `jawolskimanowski@gmail.com`

The source's internal Hello page displays these credits as well.

---

## Copyable symbols

These are the literal glyphs used by the interface or its examples. Copy them from this block when needed:

```text
◆
▼
▲
→
·
•
#
```

The default text glyph for the mobile toggle is `◆`. The dropdown uses `▼` when closed and `▲` when open. The notification title separator is `·`.

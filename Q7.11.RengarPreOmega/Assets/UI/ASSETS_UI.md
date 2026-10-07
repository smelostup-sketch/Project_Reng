# UI ASSET KIT v0 (Q7.10) — интерфейс сразу из ассетов
Набор для фаз P1–P4 из ROADMAP_UI.md. Никаких programmatic-заглушек в финальном UI:
плашки/рамки — арт, иконки/контролы — вектор, шрифты — OFL с кириллицей, звук — синт.
Импорт в Godot 4.7 проверен headless: 0 ошибок (SVG через ThorVG, шрифты variable TTF,
wav — AudioStreamWAV).

## Инвентарь и применение
| Файл | Назначение | Как использовать в Godot |
|---|---|---|
| `fonts/PlayfairDisplay.ttf` (+Italic, var wght) | Заголовки, display-текст (кириллица ✓) | FontFile; в Theme: заголовки панелей/меню |
| `fonts/Inter.ttf` (var opsz,wght) | Основной текст, цифры, подписи (кириллица ✓) | FontFile: body-текст, значения настроек |
| `fonts/OFL-*.txt` | Лицензии SIL OFL 1.1 | хранить рядом (требование OFL) |
| `textures/panel_plate.jpg` (1024²) | Плашка панели/окна настроек: золотая hextech-рамка со скошенными углами, тёмное стекло | TextureRect (stretch keep_aspect) ИЛИ NinePatchRect с patch_margin ≈ 90 px по краям (рамка равномерная) |
| `textures/button_plate.jpg` (1024²) | Плашка крупной кнопки меню: широкая, золото + бирюзовое свечение | NinePatchRect patch_margin ≈ 120 px слева/справа (концы с алмазами) |
| `textures/parchment_dark.jpg` (1024²) | Фон-подложка под контент панелей (tileable) | TextureRect tile / StyleBox-текстура с modulate alpha |
| `icons/*.svg` (13) | gear, audio, video, controls, back, exit, arrow_left/up/right (телеграф-стиль для будущего HUD-индикатора блока), shield, pip_gold, pip_purple, ult | TextureRect / Button icon; SVG масштабируется без потерь |
| `controls/*.svg` (5) | slider_track, slider_grabber (ромб), checkbox_off/on (скошенный бокс), separator (линия с ромбом) | Theme-части HSlider/CheckBox/Separator |
| `sfx/ui_hover.wav` | тик наведения | шина UI (создать в P1) |
| `sfx/ui_press.wav` | нажатие | шина UI |
| `sfx/ui_confirm.wav` | подтверждение (квинта 660→990) | шина UI |
| `sfx/ui_back.wav` | возврат (нисходящий) | шина UI |
| `sfx/ui_panel_open.wav` | открытие панели (мягкий whoosh + низ) | шина UI |

## Стиль-ДНК (зафиксирован китом)
Палитра: `#010A13`/`#0A1428` фон, золото `#C8AA6E`/`#F0E6D2`/`#C89B3C`, бирюза-акцент
`#0AC8B9` (свечение кнопки), фиолет `#7B3FA0`/`#C77DFF` (ульта/стаки). Формы: скошенные
углы, двойной золотой контур, ромбы-акценты. Типографика: Playfair (заголовки) + Inter (текст).

## Звук — происхождение
`sfx/*.wav` — процедурный синтез (python, 44.1 кГц 16 бит mono, нормализация 0.35):
прецедент в проекте уже был (проц-звук в старом EnemyHP). Качество v0 — «тихий аккуратный
тик»; замена на заказные/пак-звуки — без смены кода (те же имена файлов).

## Что НЕ в ките (осознанно)
- Курсор (нужен альфа-PNG с точным хотспотом) — P4, из арта рамки или заказа.
- Состояния hover/pressed плашек: v0 — modulate-подсветка (золото +8% яркости / бирюза),
  отдельные арт-состояния — при заказе у художника.
- Фон главного меню (P5).

## Интеграция (следующая версия, P1 из ROADMAP_UI)
SettingsService (autoload, реестр настроек data-driven, ConfigFile user://) +
SettingsPanel + PauseMenu: панель строится НАД panel_plate (NinePatch), строки настроек —
реестр → иконки из icons/, контролы из controls/, звуки на шине UI; ESC-меню — button_plate.
Визуал проверяет заказчик LIVE; структура — headless-стендом (sim_settings.gd в P1).

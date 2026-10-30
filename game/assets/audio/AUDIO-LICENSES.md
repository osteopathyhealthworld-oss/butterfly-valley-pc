# Звуковая библиотека «Мышиной саги» — происхождение и лицензии

На 29 октября 2026 года в `assets/audio/` включено **245 звуковых эффектов и 11 музыкальных композиций** (всего 256 файлов, 39.1 МиБ). Все включённые записи имеют обозначение **Creative Commons Zero 1.0 (CC0)** в опубликованных источниках. Музыка и звуки используются в игре и могут переноситься вместе с проектом в Godot. Указания авторов не меняют условия CC0.

## Природные звуки, предметы, интерфейс

Записи `sfx/*` собраны из открытой библиотеки [gamedustry](https://github.com/newrare/gamedustry/tree/main/assets/audio/sfx), которая ведёт [сводный реестр происхождения](https://github.com/newrare/gamedustry/blob/main/assets/audio/sfx/sources.tsv) и [разъяснение лицензий](https://github.com/newrare/gamedustry/blob/main/assets/audio/sfx/LICENSES.md). Среди исходных правообладателей — Kenney и авторы OpenGameArt. Мы отобрали только файлы, отмеченные в реестре как `CC0 1.0`.

| Категория | Файлов | Объём |
|---|---:|---:|
| Природа и погода | 19 | 9.58 МиБ |
| Шаги и поверхности | 21 | 0.17 МиБ |
| Сбор ресурсов | 33 | 0.53 МиБ |
| Строительство | 35 | 0.36 МиБ |
| Огород и вода | 12 | 0.27 МиБ |
| Алхимия и магия | 21 | 0.81 МиБ |
| Животные и существа | 26 | 0.54 МиБ |
| Предметы, книги и двери | 16 | 0.45 МиБ |
| Бои и удары | 19 | 0.27 МиБ |
| Интерфейс и награды | 43 | 0.81 МиБ |

## Музыка — CC0

| Композиция | Автор | Оригинальный источник | Локальный файл |
|---|---|---|---|
| Town Theme RPG | cynicmusic | [Страница автора](https://opengameart.org/content/town-theme-rpg) | `music/town-theme.mp3` |
| Medieval: The Bard's Tale | RandomMind | [Страница автора](https://opengameart.org/content/medieval-the-bards-tale) | `music/bard-tale.mp3` |
| Medieval: Battle | RandomMind | [Страница автора](https://opengameart.org/content/medieval-battle) | `music/medieval-battle.mp3` |
| ludum-dare-30-02.ogg | Abstraction / Tallbeard Studios (Benjamin Burnes) | [Страница автора](https://tallbeard.itch.io/music-loop-bundle) | `music/ludum-dare-30-02.ogg` |
| ludum-dare-30-03.ogg | Abstraction / Tallbeard Studios (Benjamin Burnes) | [Страница автора](https://tallbeard.itch.io/music-loop-bundle) | `music/ludum-dare-30-03.ogg` |
| ludum-dare-32-05.ogg | Abstraction / Tallbeard Studios (Benjamin Burnes) | [Страница автора](https://tallbeard.itch.io/music-loop-bundle) | `music/ludum-dare-32-05.ogg` |
| ludum-dare-38-08.ogg | Abstraction / Tallbeard Studios (Benjamin Burnes) | [Страница автора](https://tallbeard.itch.io/music-loop-bundle) | `music/ludum-dare-38-08.ogg` |
| ludum-dare-38-10.ogg | Abstraction / Tallbeard Studios (Benjamin Burnes) | [Страница автора](https://tallbeard.itch.io/music-loop-bundle) | `music/ludum-dare-38-10.ogg` |
| patreon-challenge-04.ogg | Abstraction / Tallbeard Studios (Benjamin Burnes) | [Страница автора](https://tallbeard.itch.io/music-loop-bundle) | `music/patreon-challenge-04.ogg` |
| Cathedral in the forest | congusbongus | [Страница автора](https://opengameart.org/content/cathedral-in-the-forest-ambient-loop) | `music/oga-cathedral-forest.ogg` |
| Dark Shrine Loop | qubodup | [Страница автора](https://opengameart.org/content/dark-shrine-loop) | `music/oga-dark-shrine.ogg` |

Материалы `ludum-dare-*` и `patreon-challenge-04` происходят из [Free Music Loop Bundle](https://tallbeard.itch.io/music-loop-bundle) студии Abstraction / Tallbeard Studios. Мы взяли независимые локальные копии из открытого проекта [Moonshard Warden](https://github.com/euuuuuuan/moonshard-warden-public), где сохранены [лицензии и происхождение](https://github.com/euuuuuuan/moonshard-warden-public/blob/main/LICENSES.md). `Town Theme RPG` опубликована композитором cynicmusic как CC0; `Medieval: The Bard's Tale` и `Medieval: Battle` опубликованы RandomMind как CC0.

## Точный реестр файлов

Для каждого звука и трека в [`catalog.json`](./catalog.json) указаны исходный файл, размер, его Git SHA, исходная библиотека, название набора, авторский источник и лицензия. Аудиофайлы скопированы в проект без перекодирования. Названия и условия лицензирования других материалов игры приведены в `../../ASSET-LICENSES.md`.

## Практические условия

- CC0 позволяет использовать записи в бесплатной и платной игре, изменять их и распространять вместе с проектом. Упоминание авторов остаётся хорошей практикой.
- Никогда не считать всё содержимое GitHub-репозитория или OpenGameArt автоматически свободным: этот каталог содержит только проверенные позиции. Списки источников нужно перепроверять при добавлении новых записей.
- Наличие CC0 не является гарантией отсутствия прав третьих лиц или совпадений с зарегистрированной музыкой. При коммерческом выпуске полезна повторная юридическая и звуковая проверка.
- Файлы из библиотеки не загружаются все при запуске. Звуки событий считываются по мере использования; дорожки природы и музыка меняются по состоянию мира. В Godot следует применять потоковое воспроизведение длинных записей.

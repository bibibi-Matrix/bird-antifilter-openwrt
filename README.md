# bird-openwrt

Пакет **OpenWrt** (прошивочный feed) с LuCI-интерфейсом, портирующий проект
[bibibi-Matrix/bird-antifilter-mikrotik](https://github.com/bibibi-Matrix/bird-antifilter-mikrotik)
из Docker/MikroTik-контейнера в нативный OpenWrt-демон BIRD2.

## Возможности

- **BGP-сервер**: раздаёт антифильтрованные маршруты (из списков) внешним BGP-пирам (пассивный режим, как в оригинале).
- **BGP-клиент**: локальные списки превращаются в статические маршруты BIRD и устанавливаются в таблицу маршрутизации ядра — трафик из списка уходит через wireguard/amneziawg-интерфейс, остальной остаётся на WAN (default route не затрагивается).
- Автозагрузка списков с `antifilter.download` и `antifilter.network`.
- Кастомные списки из папки проекта (`list_custom/*.lst`).
- Расписание синхронизации (cron) через UCI.
- Полное управление через LuCI.

## Состав

```
bird/                 # пакет демона (feed)
  Makefile
  files/
    etc/config/bird           # UCI-схема
    etc/uci-defaults/80_bird  # инициализация на первом старте
    etc/init.d/bird           # procd init + генератор bird.conf
    usr/sbin/bird-sync.sh     # скачивание/сравнение/конвертация списков
    usr/share/bird/list_custom/*.lst
luci-app-bird/        # LuCI приложение (JS-view)
  Makefile
  htdocs/luci-static/resources/view/bird/{status,config,lists,sync}.js
  root/usr/share/luci/menu.d/luci-app-bird.json
  root/usr/share/rpcd/acl.d/luci-app-bird.json
  root/usr/share/rpcd/ucode/bird.uc
```

## UCI (`/etc/config/bird`)

```sh
config bird 'global'
	option enabled '1'
	option router_id 'auto'
	option local_as '64500'
	option via_interface 'amneziawg0'
	option sync_cron '1'
	option cron_expr '0 3 * * *'

config bgp_peer 'peer1'
	option enabled '1'
	option role 'server'
	option neighbor '192.168.34.1'
	option remote_as '64501'
	option local_ip '192.168.34.2'
	option passive '1'
	option next_hop_self '1'

config source 'antifilter'
	option antifilter_download '1'
	option allyouneed '1'
	...
```

## Сборка (OpenWrt SDK / buildroot)

Репозиторий является полноценным OpenWrt-фидом: пакеты лежат в подкаталогах
`bird/` и `luci-app-bird/` (каждый со своим `Makefile`).

### Как подключить как feed

Добавьте в `feeds.conf` вашего OpenWrt-дерева строку:

```
src-git birdwrt https://github.com/<your-user>/bird-openwrt.git
```

Затем обновите и установите пакеты:

```sh
./scripts/feeds update birdwrt
./scripts/feeds install bird luci-app-bird
make defconfig
```

### Сборка пакетов

```sh
make package/feeds/birdwrt/bird/compile        # или: ./scripts/feeds install -d y bird
make package/feeds/birdwrt/luci-app-bird/compile
```

Либо вручную включите в `menuconfig`:
- `Network -> Routing and Redirection -> bird`
- `LuCI -> Applications -> luci-app-bird`

Готовые `.ipk` появятся в `bin/packages/<arch>/`.

### Локальная разработка через src-link (без публикации feed)

```sh
mkdir -p feeds/birdwrt
ln -s /путь/к/bird-openwrt feeds/birdwrt/bird-openwrt
echo "src-link birdwrt feeds/birdwrt/bird-openwrt" >> feeds.conf.default
./scripts/feeds update birdwrt
./scripts/feeds install bird luci-app-bird
make package/feeds/birdwrt/bird/compile package/feeds/birdwrt/luci-app-bird/compile
```

### Непрерывная интеграция

`.github/workflows/build.yml` собирает оба пакета в официальном SDK-контейнере
(`ghcr.io/openwrt/sdk`, конфигурируемый `sdk_tags` input, по умолчанию
`x86_64-24.10`). Запускается на push/PR/через `workflow_dispatch`; артефакты
`.ipk` выгружаются как GitHub Actions artifacts.

> Примечание: `bird` зависит от `bird2`/`bird2c` из стандартного feed `routing`,
> поэтому workflow обновляет `base packages routing luci` перед сборкой.

## Управление демоном

```sh
/etc/init.d/bird start|stop|restart|reload
/etc/init.d/bird status    # birdc show protocols
/etc/init.d/bird sync      # запуск синхронизации списков
```

Генерируемый конфиг: `/etc/bird/bird.conf`.
Рабочие каталоги: `/etc/bird/list`, `/etc/bird/list_rsc`, `/etc/bird/list_custom`.

## Примечания

- Требуются пакеты: `bird2`, `bird2c`, `curl`/`wget`, `iproute2`.
- Для wireguard установите штатный `wireguard` либо `amneziawg` (интерфейс `amneziawg0`), укажите имя интерфейса в `bird.global.via_interface`.
- Пакет рассчитан на OpenWrt 24.10+ (JS-view LuCI, ucode rpcd).

Дисклеймер: проект создан в ознакомительных целях. Используйте на свой страх и риск.

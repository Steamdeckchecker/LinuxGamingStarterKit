#!/usr/bin/env bash
# Linux Handheld Starter Kit — Steam Deck Checker — 0.1.0
# Run as your normal desktop user: bash install.sh
# The embedded Python code uses only the standard library.
set -euo pipefail
if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' 'Python 3.9+ is required. Bitte Python 3.9+ installieren.' >&2
    exit 1
fi
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))'; then
    printf '%s\n' 'Python 3.9+ is required.' >&2
    exit 1
fi
STARTER_KIT_BASE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export STARTER_KIT_BASE
# GUI launches from a file manager get a terminal for live progress as well.
starter_kit_diagnostics=0
for starter_kit_arg in "$@"; do
    case "$starter_kit_arg" in --check|--help|-h) starter_kit_diagnostics=1 ;; esac
done
if [[ ! -t 1 && "$starter_kit_diagnostics" == 0 && "${STARTER_KIT_TERMINAL:-0}" != 1 ]] && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    export STARTER_KIT_TERMINAL=1
    starter_kit_script="$STARTER_KIT_BASE/$(basename -- "${BASH_SOURCE[0]}")"
    if command -v konsole >/dev/null 2>&1; then
        exec konsole --separate --nofork -e bash "$starter_kit_script" "$@"
    elif command -v gnome-terminal >/dev/null 2>&1; then
        exec gnome-terminal --wait -- bash "$starter_kit_script" "$@"
    elif command -v xterm >/dev/null 2>&1; then
        exec xterm -e bash "$starter_kit_script" "$@"
    fi
fi
starter_kit_work="$(mktemp -d -t handheld-starter-kit-launcher.XXXXXXXX)"
chmod 700 "$starter_kit_work"
starter_kit_child=''
starter_kit_cleanup() {
    rm -rf -- "$starter_kit_work"
}
starter_kit_stop() {
    if [[ -n "$starter_kit_child" ]]; then
        kill -TERM "$starter_kit_child" 2>/dev/null || true
        wait "$starter_kit_child" 2>/dev/null || true
    fi
    exit 130
}
trap starter_kit_cleanup EXIT
trap starter_kit_stop INT TERM
cat > "$starter_kit_work/starterkit.py" <<'HANDHELD_STARTER_KIT_PYTHON'
#!/usr/bin/env python3
"""Linux Handheld Starter Kit. Python standard library only; see README.md."""
from __future__ import annotations

import argparse
import base64
import codecs
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import logging
import os
from pathlib import Path, PurePosixPath
import pwd
import re
import selectors
import shlex
import shutil
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile
import zlib

VERSION = "0.1.0"
LANGUAGES = {"de": "Deutsch", "en": "English", "es": "Español", "fr": "Français",
             "ru": "Русский", "zh": "中文（简体）", "ja": "日本語"}
LANG_ORDER = ("en", "de", "es", "fr", "ru", "zh", "ja")


def L(en, de, es, fr, ru, zh, ja):
    return dict(zip(LANG_ORDER, (en, de, es, fr, ru, zh, ja)))


TEXT = {
    "yes": L("Yes", "Ja", "Sí", "Oui", "Да", "是", "はい"),
    "no": L("No", "Nein", "No", "Non", "Нет", "否", "いいえ"),
    "next": L("Continue", "Weiter", "Continuar", "Continuer", "Продолжить", "继续", "次へ"),
    "cancel": L("Cancel", "Abbrechen", "Cancelar", "Annuler", "Отмена", "取消", "キャンセル"),
    "name": L("Name", "Name", "Nombre", "Nom", "Название", "名称", "名前"),
    "description": L("Description", "Beschreibung", "Descripción", "Description", "Описание", "说明", "説明"),
    "select": L("Select", "Auswahl", "Seleccionar", "Sélection", "Выбор", "选择", "選択"),
    "device": L("1 · Select your handheld", "1 · Handheld auswählen", "1 · Elige tu consola", "1 · Choisir votre console", "1 · Выберите устройство", "1 · 选择掌机", "1 · 携帯ゲーム機を選択"),
    "other": L("Other handheld", "Anderer Handheld", "Otra consola", "Autre console", "Другое устройство", "其他掌机", "その他の携帯ゲーム機"),
    "password": L("2 · Administrator password", "2 · Administratorpasswort", "2 · Contraseña de administrador", "2 · Mot de passe administrateur", "2 · Пароль администратора", "2 · 管理员密码", "2 · 管理者パスワード"),
    "create_pw": L("No password is set. Create one now? A terminal will open for the system's passwd tool.", "Es ist kein Passwort gesetzt. Jetzt eines erstellen? Dafür öffnet sich ein Terminal mit dem Systemwerkzeug passwd.", "No hay contraseña. ¿Crear una ahora? Se abrirá una terminal con passwd.", "Aucun mot de passe défini. En créer un ? Un terminal avec passwd va s'ouvrir.", "Пароль не задан. Создать его сейчас? Откроется терминал с passwd.", "尚未设置密码。现在创建吗？将打开终端并运行系统 passwd 工具。", "パスワードが未設定です。作成しますか？端末で passwd が開きます。"),
    "unknown_pw": L("Password status is unavailable or the account is locked. Open passwd to set/change it? Choose No to try the existing password.", "Der Passwortstatus ist unbekannt oder das Konto ist gesperrt. passwd zum Setzen/Ändern öffnen? Mit Nein wird das vorhandene Passwort versucht.", "Estado de contraseña desconocido o cuenta bloqueada. ¿Abrir passwd? No permite probar la contraseña actual.", "État du mot de passe inconnu ou compte verrouillé. Ouvrir passwd ? Non permet d'essayer le mot de passe actuel.", "Статус пароля неизвестен или учётная запись заблокирована. Открыть passwd? Нет — попробовать текущий пароль.", "无法确定密码状态，或账户已锁定。打开 passwd 设置或修改密码吗？选择否则尝试现有密码。", "パスワードの状態が不明、またはアカウントがロックされています。passwd を開きますか？「いいえ」で既存のパスワードを試します。"),
    "auth": L("3 · Authorize administrator actions", "3 · Administratoraktionen autorisieren", "3 · Autorizar acciones de administrador", "3 · Autoriser les opérations administrateur", "3 · Разрешить действия администратора", "3 · 授权管理员操作", "3 · 管理者操作を許可"),
    "auth_text": L("Enter your Linux user password again to authorize the following administrator actions. It will not be saved.", "Bitte dein Linux-Benutzerpasswort erneut eingeben, um die folgenden Administratoraktionen zu autorisieren. Es wird nicht gespeichert.", "Introduce otra vez tu contraseña de Linux para autorizar las acciones. No se guardará.", "Saisissez à nouveau votre mot de passe Linux pour autoriser les opérations. Il ne sera pas enregistré.", "Введите пароль Linux ещё раз для разрешения дальнейших действий. Он не сохраняется.", "请再次输入 Linux 用户密码，以授权后续管理员操作。密码不会保存。", "今後の管理者操作を許可するため、Linux のパスワードを再入力してください。保存されません。"),
    "auth_failed": L("Authorization failed. Try again?", "Die Autorisierung ist fehlgeschlagen. Erneut versuchen?", "Falló la autorización. ¿Reintentar?", "Échec de l'autorisation. Réessayer ?", "Авторизация не удалась. Повторить?", "授权失败。重试吗？", "認証に失敗しました。再試行しますか？"),
    "no_admin": L("Administrator access is unavailable. Videos and user Flatpaks remain available; Decky installation is skipped.", "Keine Administratorberechtigung verfügbar. Videos und Benutzer-Flatpaks sind weiterhin möglich; die Decky-Installation wird übersprungen.", "Sin permisos de administrador. Los vídeos y Flatpaks de usuario siguen disponibles; se omite Decky.", "Droits administrateur indisponibles. Vidéos et Flatpaks utilisateur restent possibles ; Decky sera ignoré.", "Нет прав администратора. Видео и пользовательские Flatpak доступны; установка Decky пропускается.", "无法取得管理员权限。仍可安装视频和用户级 Flatpak；将跳过 Decky 安装。", "管理者権限を取得できません。動画とユーザー用 Flatpak は利用できますが、Decky のインストールはスキップします。"),
    "videos": L("4 · Steam startup videos", "4 · Steam-Startvideos", "4 · Vídeos de inicio de Steam", "4 · Vidéos de démarrage Steam", "4 · Стартовые видео Steam", "4 · Steam 启动视频", "4 · Steam 起動動画"),
    "videos_text": L("Select a video pack. The matching device is preselected.\nDestination: {path}", "Videopaket auswählen. Das passende Gerät ist vorausgewählt.\nZiel: {path}", "Elige un paquete. Se preselecciona tu dispositivo.\nDestino: {path}", "Choisissez un pack. Votre appareil est présélectionné.\nDestination : {path}", "Выберите набор. Ваше устройство выбрано заранее.\nПапка: {path}", "选择视频包，默认已选中对应设备。\n目标目录：{path}", "動画パックを選択してください。選んだ機種が初期選択されています。\n保存先：{path}"),
    "no_videos": L("No startup videos", "Keine Startvideos", "Sin vídeos de inicio", "Aucune vidéo", "Без стартовых видео", "不安装启动视频", "起動動画をインストールしない"),
    "video_done": L("Videos installed. Enable them in Game Mode under Settings → Customization → Startup Movie.", "Videos installiert. Bitte im Game Mode unter Einstellungen → Anpassungen → Startvideo aktivieren.", "Vídeos instalados. Actívalos en modo juego: Ajustes → Personalización → Vídeo de inicio.", "Vidéos installées. Activez-les en mode jeu : Paramètres → Personnalisation → Vidéo de démarrage.", "Видео установлены. Включите их в игровом режиме: Настройки → Персонализация → Стартовое видео.", "视频已安装。请在游戏模式的“设置 → 自定义 → 启动视频”中启用。", "動画をインストールしました。ゲームモードの「設定 → カスタマイズ → 起動動画」で有効にしてください。"),
    "decky": L("5 · Decky Loader", "5 · Decky Loader", "5 · Decky Loader", "5 · Decky Loader", "5 · Decky Loader", "5 · Decky Loader", "5 · Decky Loader"),
    "decky_q": L("Install the current stable Decky Loader?", "Die aktuelle stabile Version von Decky Loader installieren?", "¿Instalar la versión estable de Decky Loader?", "Installer la version stable de Decky Loader ?", "Установить стабильную версию Decky Loader?", "安装当前稳定版 Decky Loader 吗？", "現在の安定版 Decky Loader をインストールしますか？"),
    "decky_exists": L("Decky Loader is already installed. Continue to plugin selection?", "Decky Loader ist bereits installiert. Weiter zur Plugin-Auswahl?", "Decky Loader ya está instalado. ¿Continuar con los plugins?", "Decky Loader est déjà installé. Passer aux plugins ?", "Decky Loader уже установлен. Перейти к плагинам?", "已安装 Decky Loader。继续选择插件吗？", "Decky Loader はインストール済みです。プラグインの選択に進みますか？"),
    "plugins": L("6 · Decky plugins", "6 · Decky-Plugins", "6 · Plugins de Decky", "6 · Plugins Decky", "6 · Плагины Decky", "6 · Decky 插件", "6 · Decky プラグイン"),
    "plugin_q": L("How would you like to select plugins?", "Wie möchtest du Plugins auswählen?", "¿Cómo quieres seleccionar los plugins?", "Comment choisir les plugins ?", "Как выбрать плагины?", "如何选择插件？", "プラグインの選び方を選択してください。"),
    "recommended": L("Recommended plugins", "Empfohlene Plugins", "Plugins recomendados", "Plugins recommandés", "Рекомендуемые плагины", "推荐插件", "おすすめプラグイン"),
    "from_list": L("Choose from list (most stars first)", "Aus Liste auswählen (meiste Sterne zuerst)", "Elegir de la lista (más estrellas primero)", "Choisir dans la liste (étoiles décroissantes)", "Выбрать из списка (по звёздам)", "从列表选择（按星标降序）", "一覧から選択（スター数の多い順）"),
    "missing_recommend": L("recommend.txt was not found beside install.sh. Select the file now, or cancel to return to the plugin menu.", "recommend.txt wurde neben install.sh nicht gefunden. Jetzt die Datei auswählen oder mit Abbrechen zum Plugin-Menü zurückkehren.", "No se encuentra recommend.txt junto a install.sh. Selecciona el archivo o cancela para volver.", "recommend.txt est absent à côté de install.sh. Choisissez le fichier ou annulez pour revenir.", "Файл recommend.txt рядом с install.sh не найден. Выберите файл или отмените для возврата.", "未在 install.sh 旁找到 recommend.txt。请选择文件，或取消以返回插件菜单。", "install.sh と同じ場所に recommend.txt がありません。ファイルを選択するか、キャンセルして戻ってください。"),
    "search": L("Filter by name, repository or description. Leave empty to show all plugins.", "Nach Name, Repository oder Beschreibung filtern. Leer lassen, um alle Plugins anzuzeigen.", "Filtra por nombre, repositorio o descripción. Vacío muestra todos.", "Filtrer par nom, dépôt ou description. Laisser vide pour tout afficher.", "Фильтр по названию, репозиторию или описанию. Пусто — показать все.", "按名称、仓库或说明筛选。留空显示全部插件。", "名前、リポジトリ、説明で絞り込みます。空欄ですべて表示します。"),
    "plugin_list": L("Check plugins to install. Sorted by GitHub stars. Descriptions are supplied by the projects.", "Gewünschte Plugins anhaken. Nach GitHub-Sternen sortiert. Die Beschreibungen stammen von den Projekten.", "Marca plugins. Ordenados por estrellas. Las descripciones son de cada proyecto.", "Cochez les plugins. Tri par étoiles. Descriptions fournies par les projets.", "Отметьте плагины. Сортировка по звёздам. Описания предоставлены проектами.", "勾选要安装的插件，按 GitHub 星标排序。说明由各项目提供。", "インストールするプラグインを選択してください。スター数順です。説明は各プロジェクトの原文です。"),
    "no_matches": L("No matching plugins. Return to the filter?", "Keine passenden Plugins gefunden. Zum Filter zurückkehren?", "Sin resultados. ¿Volver al filtro?", "Aucun résultat. Revenir au filtre ?", "Совпадений нет. Вернуться к фильтру?", "没有匹配的插件。返回筛选吗？", "一致するプラグインがありません。絞り込みに戻りますか？"),
    "apps": L("7 · Additional applications", "7 · Weitere Anwendungen", "7 · Aplicaciones adicionales", "7 · Applications supplémentaires", "7 · Дополнительные приложения", "7 · 其他应用", "7 · 追加アプリ"),
    "apps_text": L("Check the applications you want. Installed apps are reused. Downloads and installations run one at a time.", "Gewünschte Anwendungen anhaken. Installierte Apps werden weiterverwendet. Downloads und Installationen laufen einzeln nacheinander.", "Marca las aplicaciones. Se reutilizan las ya instaladas. Descargas e instalaciones una a una.", "Cochez les applications. Les applications déjà installées sont conservées. Opérations une par une.", "Отметьте приложения. Уже установленные используются повторно. Все операции выполняются по очереди.", "勾选所需应用。已安装的应用将直接使用。下载和安装依次执行。", "必要なアプリを選択してください。インストール済みのアプリは再利用し、処理は順番に実行します。"),
    "add_steam": L("Add the successfully installed/selected apps as non-Steam games? Steam will close while the library is updated, then restart automatically after a 3-second wait.", "Die erfolgreich installierten/ausgewählten Apps als steamfremde Spiele hinzufügen? Steam wird zum Aktualisieren beendet und nach drei Sekunden Wartezeit automatisch wieder gestartet.", "¿Añadir las aplicaciones seleccionadas e instaladas como juegos externos a Steam? Steam se cerrará para actualizar la biblioteca y volverá a iniciarse automáticamente tras esperar 3 segundos.", "Ajouter les applications sélectionnées et installées comme jeux non-Steam ? Steam sera fermé pour la mise à jour, puis relancé automatiquement après 3 secondes d’attente.", "Добавить установленные выбранные приложения как сторонние игры? Steam закроется для обновления библиотеки и автоматически запустится после паузы в 3 секунды.", "将成功安装或已安装的所选应用添加为非 Steam 游戏吗？更新库时将关闭 Steam，等待 3 秒后自动重新启动。", "選択したインストール済みアプリを非 Steam ゲームとして追加しますか？ライブラリの更新中は Steam を終了し、3 秒待ってから自動的に再起動します。"),
    "close_steam": L("Steam will now close. Finish any game or download first. Continue?", "Steam wird jetzt beendet. Bitte vorher Spiele und Downloads abschließen. Fortfahren?", "Steam se cerrará. Termina tus juegos y descargas. ¿Continuar?", "Steam va se fermer. Terminez vos jeux et téléchargements. Continuer ?", "Steam будет закрыт. Сначала завершите игры и загрузки. Продолжить?", "即将关闭 Steam。请先结束游戏和下载。继续吗？", "Steam を終了します。ゲームやダウンロードを終えてから続行してください。続行しますか？"),
    "profile": L("Select the Steam account to receive the shortcuts.", "Steam-Konto auswählen, dem die Verknüpfungen hinzugefügt werden sollen.", "Elige la cuenta de Steam para los accesos directos.", "Choisissez le compte Steam pour les raccourcis.", "Выберите учётную запись Steam для ярлыков.", "选择用于添加快捷方式的 Steam 账户。", "ショートカットを追加する Steam アカウントを選択してください。"),
    "steam_done": L("Steam shortcuts saved. Steam is running again.", "Steam-Verknüpfungen gespeichert. Steam wurde wieder gestartet.", "Accesos directos guardados. Steam está en ejecución de nuevo.", "Raccourcis enregistrés. Steam a été relancé.", "Ярлыки сохранены. Steam снова запущен.", "Steam 快捷方式已保存，Steam 已重新启动。", "Steam ショートカットを保存し、Steam を再起動しました。"),
    "emulation": L("8 · Emulation", "8 · Emulation", "8 · Emulación", "8 · Émulation", "8 · Эмуляция", "8 · 模拟器", "8 · エミュレーション"),
    "emu_q": L("Choose an emulation setup, or skip.", "Emulationslösung auswählen oder überspringen.", "Elige una solución de emulación o salta este paso.", "Choisissez une solution d'émulation ou ignorez cette étape.", "Выберите решение для эмуляции или пропустите.", "选择模拟器方案，或跳过此步骤。", "エミュレーション環境を選択するか、スキップしてください。"),
    "retro_desc": L("All-in-one Flatpak emulation suite", "Emulationspaket als Flatpak", "Suite de emulación Flatpak", "Suite d'émulation Flatpak", "Комплект эмуляторов Flatpak", "一体化 Flatpak 模拟器套件", "Flatpak 形式の統合エミュレーター"),
    "emu_desc": L("Official EmuDeck setup; finish its wizard and close it to continue", "Offizielle EmuDeck-Einrichtung; Assistent abschließen und zum Fortfahren schließen", "Configuración oficial; completa y cierra su asistente para continuar", "Configuration officielle ; terminez et fermez l'assistant pour continuer", "Официальная настройка; завершите и закройте мастер для продолжения", "官方 EmuDeck 安装；完成并关闭其向导后继续", "公式 EmuDeck セットアップ。ウィザードを完了して閉じると続行します"),
    "emu_wait": L("The official EmuDeck application will open. Complete its setup and close the application. The Starter Kit waits until it exits.", "Die offizielle EmuDeck-Anwendung öffnet sich. Bitte die Einrichtung abschließen und die Anwendung schließen. Das Starter Kit wartet bis zum Beenden.", "Se abrirá EmuDeck oficial. Completa su configuración y ciérralo. El Starter Kit esperará.", "EmuDeck officiel va s'ouvrir. Terminez la configuration puis fermez-le. Le Starter Kit attend sa fermeture.", "Откроется официальный EmuDeck. Завершите настройку и закройте его. Starter Kit будет ждать.", "即将打开官方 EmuDeck 应用。请完成设置并关闭应用。Starter Kit 会等待其退出。", "公式 EmuDeck が開きます。セットアップを完了し、アプリを閉じてください。Starter Kit は終了まで待機します。"),
    "finish": L("9 · Finished", "9 · Abgeschlossen", "9 · Finalizado", "9 · Terminé", "9 · Завершено", "9 · 完成", "9 · 完了"),
    "reboot": L("Setup is finished. Restart now to activate the changes?", "Die Einrichtung ist abgeschlossen. Jetzt neu starten, um die Änderungen zu aktivieren?", "Configuración terminada. ¿Reiniciar ahora para activar los cambios?", "Configuration terminée. Redémarrer maintenant pour activer les changements ?", "Настройка завершена. Перезагрузить сейчас для применения изменений?", "设置已完成。现在重启以应用更改吗？", "セットアップが完了しました。変更を有効にするため、今すぐ再起動しますか？"),
    "summary": L("Completed: {ok}\nFailed: {failed}\nSkipped: {skipped}\n\nLog: {log}", "Erfolgreich: {ok}\nFehlgeschlagen: {failed}\nÜbersprungen: {skipped}\n\nProtokoll: {log}", "Completado: {ok}\nFallido: {failed}\nOmitido: {skipped}\n\nRegistro: {log}", "Réussi : {ok}\nÉchec : {failed}\nIgnoré : {skipped}\n\nJournal : {log}", "Успешно: {ok}\nОшибок: {failed}\nПропущено: {skipped}\n\nЖурнал: {log}", "成功：{ok}\n失败：{failed}\n跳过：{skipped}\n\n日志：{log}", "成功：{ok}\n失敗：{failed}\nスキップ：{skipped}\n\nログ：{log}"),
    "failed": L("{item} failed.\n{error}\n\nThe next step will only start after this message is closed.", "{item} ist fehlgeschlagen.\n{error}\n\nDer nächste Schritt beginnt erst nach dem Schließen dieser Meldung.", "Falló {item}.\n{error}\n\nEl siguiente paso esperará a que cierres este mensaje.", "Échec : {item}.\n{error}\n\nL'étape suivante attend la fermeture de ce message.", "Ошибка: {item}.\n{error}\n\nСледующий шаг начнётся после закрытия сообщения.", "{item} 失败。\n{error}\n\n关闭此消息后才会开始下一步。", "{item} に失敗しました。\n{error}\n\nこのメッセージを閉じるまで、次の処理は始まりません。"),
    "working": L("Please wait. This operation must finish before continuing.", "Bitte warten. Dieser Vorgang muss vor dem Fortfahren abgeschlossen sein.", "Espera. Esta operación debe terminar antes de continuar.", "Veuillez patienter. Cette opération doit se terminer avant de continuer.", "Подождите. Операция должна завершиться перед продолжением.", "请稍候。必须等此操作完成后才能继续。", "お待ちください。処理が完了してから次に進みます。"),
    "dry": L("SIMULATION: no installations, password changes or restart will be performed.", "SIMULATION: Es werden keine Installationen, Passwortänderungen oder Neustarts durchgeführt.", "SIMULACIÓN: sin instalaciones, cambios de contraseña ni reinicio.", "SIMULATION : aucune installation, modification de mot de passe ou redémarrage.", "СИМУЛЯЦИЯ: без установки, изменения пароля и перезагрузки.", "模拟模式：不会安装、修改密码或重启。", "シミュレーション：インストール、パスワード変更、再起動は実行しません。"),
    "no_gui": L("Run in Desktop Mode with zenity or kdialog installed.", "Bitte im Desktop-Modus mit installiertem zenity oder kdialog starten.", "Ejecuta en modo escritorio con zenity o kdialog instalado.", "Lancez en mode bureau avec zenity ou kdialog installé.", "Запустите в режиме рабочего стола с zenity или kdialog.", "请在桌面模式下运行，并安装 zenity 或 kdialog。", "zenity または kdialog のあるデスクトップモードで実行してください。"),
    "root": L("Start install.sh as your normal desktop user, without sudo. Administrator rights are requested inside the wizard.", "install.sh als normalen Desktop-Benutzer ohne sudo starten. Administratorrechte werden im Assistenten angefragt.", "Ejecuta install.sh como usuario normal, sin sudo. El asistente pedirá permisos.", "Lancez install.sh en utilisateur normal, sans sudo. L'assistant demandera les droits.", "Запустите install.sh от обычного пользователя без sudo. Мастер сам запросит права.", "请以普通桌面用户运行 install.sh，不要使用 sudo。向导会请求管理员权限。", "install.sh は sudo を使わず通常のユーザーで起動してください。管理者権限はウィザード内で要求されます。"),
    "no_steam": L("No Steam installation/profile was found. Open Steam once, sign in, and run this step again.", "Keine Steam-Installation bzw. kein Profil gefunden. Steam einmal öffnen, anmelden und diesen Schritt erneut ausführen.", "No hay instalación o perfil de Steam. Abre Steam, inicia sesión y repite.", "Aucune installation ou profil Steam trouvé. Ouvrez Steam, connectez-vous puis réessayez.", "Steam или профиль не найден. Запустите Steam, войдите в аккаунт и повторите.", "未找到 Steam 安装或用户配置。请先打开 Steam 并登录，然后重试。", "Steam またはプロフィールが見つかりません。Steam を起動してログインし、再実行してください。"),
    "no_video_files": L("No WebM startup videos were found in the selected repository's downloads.", "In den Downloads des ausgewählten Repositorys wurden keine WebM-Startvideos gefunden.", "No se encontraron vídeos WebM en las descargas del repositorio.", "Aucune vidéo WebM trouvée dans les téléchargements du dépôt.", "В загрузках репозитория нет стартовых видео WebM.", "在所选仓库的下载内容中未找到 WebM 启动视频。", "選択したリポジトリの配布物に WebM 起動動画がありません。"),
    "no_plugin_zip": L("No ready-to-install plugin archive with plugin.json and dist/index.js was found. Source code alone cannot be installed.", "Kein installierbares Plugin-Archiv mit plugin.json und dist/index.js gefunden. Reiner Quellcode kann nicht installiert werden.", "No hay archivo de plugin listo con plugin.json y dist/index.js. Solo el código fuente no basta.", "Aucune archive prête avec plugin.json et dist/index.js. Le code source seul ne suffit pas.", "Нет готового архива с plugin.json и dist/index.js. Одного исходного кода недостаточно.", "未找到含 plugin.json 和 dist/index.js 的可安装插件压缩包。仅有源代码无法直接安装。", "plugin.json と dist/index.js を含む配布用アーカイブがありません。ソースコードだけではインストールできません。"),
    "terminal_missing": L("No supported terminal found (Konsole, GNOME Terminal or xterm). Run passwd in a terminal, then restart the installer.", "Kein unterstütztes Terminal gefunden (Konsole, GNOME Terminal oder xterm). Bitte passwd im Terminal ausführen und den Installer neu starten.", "No hay terminal compatible. Ejecuta passwd en una terminal y reinicia el instalador.", "Aucun terminal compatible. Exécutez passwd dans un terminal puis relancez l'installateur.", "Нет подходящего терминала. Выполните passwd в терминале и перезапустите установщик.", "未找到支持的终端。请在终端运行 passwd，然后重启安装程序。", "対応する端末がありません。端末で passwd を実行し、インストーラーを再起動してください。"),
    "already_running": L("Another Starter Kit instance is already running.", "Das Starter Kit läuft bereits in einem anderen Fenster.", "Ya se está ejecutando otra instancia del Starter Kit.", "Une autre instance du Starter Kit est déjà en cours.", "Другой экземпляр Starter Kit уже запущен.", "Starter Kit 已在另一个窗口运行。", "Starter Kit は別のウィンドウで実行中です。"),
    "flatpak_missing": L("Flatpak is missing. Install Flatpak using your distribution's software tools, then rerun this step.", "Flatpak fehlt. Bitte Flatpak über die Softwareverwaltung deiner Distribution installieren und diesen Schritt erneut ausführen.", "Falta Flatpak. Instálalo con las herramientas de tu distribución y repite.", "Flatpak est absent. Installez-le avec les outils de votre distribution puis réessayez.", "Flatpak отсутствует. Установите его средствами дистрибутива и повторите.", "未安装 Flatpak。请使用发行版的软件工具安装后重试。", "Flatpak がありません。ディストリビューションのソフトウェア管理からインストールし、再実行してください。"),
    "steam_timeout": L("Steam is still running. No library files were modified. Close Steam completely and try again.", "Steam läuft noch. Es wurden keine Bibliotheksdateien verändert. Steam vollständig schließen und erneut versuchen.", "Steam sigue abierto. No se modificó la biblioteca. Ciérralo y repite.", "Steam fonctionne encore. Aucun fichier modifié. Fermez-le entièrement puis réessayez.", "Steam ещё работает. Файлы не изменены. Полностью закройте Steam и повторите.", "Steam 仍在运行，未修改库文件。请完全关闭 Steam 后重试。", "Steam がまだ実行中です。ライブラリは変更していません。完全に終了して再試行してください。"),
    "confirm_plugins": L("Install these plugins? Existing versions will be backed up.\n\n{items}", "Diese Plugins installieren? Vorhandene Versionen werden gesichert.\n\n{items}", "¿Instalar estos plugins? Se guardarán copias de versiones anteriores.\n\n{items}", "Installer ces plugins ? Les anciennes versions seront sauvegardées.\n\n{items}", "Установить плагины? Старые версии сохранятся в резервной копии.\n\n{items}", "安装以下插件吗？现有版本将备份。\n\n{items}", "これらのプラグインをインストールしますか？既存バージョンはバックアップします。\n\n{items}"),
    "no_description": L("No description provided", "Keine Beschreibung vorhanden", "Sin descripción", "Aucune description", "Описание отсутствует", "暂无说明", "説明なし"),
    "finished_emu": L("EmuDeck closed. Setup completion depends on the choices made in its own wizard.", "EmuDeck wurde geschlossen. Der Einrichtungsstatus hängt von den Entscheidungen im EmuDeck-Assistenten ab.", "EmuDeck cerrado. La instalación depende de las opciones elegidas en su asistente.", "EmuDeck fermé. L'installation dépend des choix faits dans son assistant.", "EmuDeck закрыт. Результат настройки зависит от действий в его мастере.", "EmuDeck 已关闭。是否完成配置取决于其向导中的操作。", "EmuDeck が終了しました。設定の完了状況は EmuDeck のウィザードでの操作によって異なります。"),
}

TEXT.update({
    "transfer": L("Downloading {name}", "Download: {name}", "Descargando {name}", "Téléchargement : {name}", "Загрузка: {name}", "正在下载：{name}", "ダウンロード：{name}"),
    "extracting": L("Extracting {name}", "Entpacken: {name}", "Extrayendo {name}", "Extraction : {name}", "Распаковка: {name}", "正在解压：{name}", "展開：{name}"),
    "executing": L("Running {name}", "Vorgang läuft: {name}", "Ejecutando {name}", "Exécution : {name}", "Выполняется: {name}", "正在运行：{name}", "実行中：{name}"),
    "copy_videos": L("Installing startup videos", "Startvideos installieren", "Instalando vídeos de inicio", "Installation des vidéos", "Установка стартовых видео", "正在安装启动视频", "起動動画をインストール中"),
    "overwrite_video": L("Writing video {index}/{total}: {name} (replace existing file)", "Video {index}/{total} schreiben: {name} (vorhandene Datei ersetzen)", "Escribiendo vídeo {index}/{total}: {name} (reemplazar si existe)", "Écriture vidéo {index}/{total} : {name} (remplacement si présent)", "Запись видео {index}/{total}: {name} (с заменой файла)", "写入视频 {index}/{total}：{name}（覆盖现有文件）", "動画 {index}/{total} を保存：{name}（既存ファイルを上書き）"),
    "builtin_recommendations": L("{count} included recommendations", "{count} integrierte Empfehlungen", "{count} recomendaciones incluidas", "{count} recommandations intégrées", "{count} встроенных рекомендаций", "内置 {count} 款推荐插件", "{count} 件のおすすめを内蔵"),
    "use_builtin": L("Using the built-in plugin recommendations; no extra file is needed.", "Integrierte Plugin-Empfehlungen verwenden; keine zusätzliche Datei erforderlich.", "Usando las recomendaciones integradas; no se necesita otro archivo.", "Utilisation des recommandations intégrées ; aucun fichier supplémentaire nécessaire.", "Используются встроенные рекомендации; дополнительный файл не нужен.", "使用内置推荐插件列表，无需其他文件。", "内蔵のおすすめリストを使用します。追加ファイルは不要です。"),
    "status_ok": L("COMPLETED", "ERFOLGREICH", "COMPLETADO", "TERMINÉ", "ГОТОВО", "已完成", "完了"),
    "status_failed": L("FAILED", "FEHLGESCHLAGEN", "ERROR", "ÉCHEC", "ОШИБКА", "失败", "失敗"),
    "status_skipped": L("SKIPPED", "ÜBERSPRUNGEN", "OMITIDO", "IGNORÉ", "ПРОПУЩЕНО", "已跳过", "スキップ"),
    "checking_source": L("Checking source: {name}", "Quelle prüfen: {name}", "Comprobando origen: {name}", "Vérification de la source : {name}", "Проверка источника: {name}", "正在检查来源：{name}", "配布元を確認：{name}"),
    "verify_download": L("Verifying download and SHA-256 when provided", "Download und gegebenenfalls SHA-256 prüfen", "Verificando descarga y SHA-256 si está disponible", "Vérification du téléchargement et du SHA-256 si fourni", "Проверка загрузки и SHA-256 при наличии", "正在校验下载文件及可用的 SHA-256", "ダウンロードと提供された SHA-256 を検証中"),
    "files_unit": L("files", "Dateien", "archivos", "fichiers", "файлов", "个文件", "ファイル"),
    "log_location": L("Live status below. Full log: {path}", "Status wird hier laufend angezeigt. Vollständiges Protokoll: {path}", "Estado en directo a continuación. Registro completo: {path}", "État en direct ci-dessous. Journal complet : {path}", "Ниже отображается ход работы. Полный журнал: {path}", "下方实时显示运行状态。完整日志：{path}", "進行状況を随時表示します。完全なログ：{path}"),
})

TEXT.update({
    "add_emulation_steam": L("Add {name} as a non-Steam game? Steam will close while the shortcut is saved, then restart automatically after a 3-second wait.", "{name} als steamfremdes Spiel hinzufügen? Steam wird zum Speichern der Verknüpfung beendet und nach drei Sekunden Wartezeit automatisch wieder gestartet.", "¿Añadir {name} como juego externo a Steam? Steam se cerrará para guardar el acceso directo y se iniciará automáticamente tras esperar 3 segundos.", "Ajouter {name} comme jeu non-Steam ? Steam sera fermé pour enregistrer le raccourci, puis relancé automatiquement après 3 secondes d’attente.", "Добавить {name} как стороннюю игру? Steam закроется для сохранения ярлыка и автоматически запустится после паузы в 3 секунды.", "将 {name} 添加为非 Steam 游戏吗？保存快捷方式时将关闭 Steam，等待 3 秒后自动重新启动。", "{name} を非 Steam ゲームとして追加しますか？ショートカットの保存中は Steam を終了し、3 秒待ってから自動的に再起動します。"),
    "steam_restart_wait": L("Steam shortcuts processed. Waiting {seconds} seconds before restarting Steam…", "Steam-Verknüpfungen verarbeitet. Vor dem Steam-Neustart {seconds} Sekunden warten …", "Accesos directos procesados. Esperando {seconds} segundos antes de reiniciar Steam…", "Raccourcis traités. Attente de {seconds} secondes avant de relancer Steam…", "Ярлыки обработаны. Ожидание {seconds} секунд перед запуском Steam…", "Steam 快捷方式已处理。等待 {seconds} 秒后重新启动 Steam……", "Steam ショートカットの処理が完了しました。再起動まで {seconds} 秒待ちます…"),
    "steam_restarting": L("Starting Steam again…", "Steam wird wieder gestartet …", "Iniciando Steam de nuevo…", "Relance de Steam…", "Повторный запуск Steam…", "正在重新启动 Steam……", "Steam を再起動しています…"),
    "steam_restart_failed": L("Steam could not be restarted or its startup could not be confirmed. Please start Steam manually. Saved shortcuts are preserved.", "Steam konnte nicht neu gestartet oder sein Start nicht bestätigt werden. Bitte Steam manuell starten. Gespeicherte Verknüpfungen bleiben erhalten.", "No se pudo reiniciar Steam o confirmar su inicio. Inícialo manualmente. Los accesos guardados se conservan.", "Impossible de relancer Steam ou de confirmer son démarrage. Lancez-le manuellement. Les raccourcis enregistrés sont conservés.", "Не удалось перезапустить Steam или подтвердить его запуск. Запустите Steam вручную. Сохранённые ярлыки остаются на месте.", "无法重新启动 Steam 或确认其已启动。请手动启动 Steam，已保存的快捷方式会保留。", "Steam の再起動を確認できませんでした。手動で起動してください。保存済みのショートカットは保持されます。"),
    "steam_launcher_missing": L("The Steam launcher was not found. Start Steam once and try again.", "Das Steam-Startprogramm wurde nicht gefunden. Bitte Steam einmal starten und erneut versuchen.", "No se encontró el lanzador de Steam. Inicia Steam una vez y vuelve a intentarlo.", "Le lanceur Steam est introuvable. Lancez Steam une fois, puis réessayez.", "Программа запуска Steam не найдена. Запустите Steam один раз и повторите попытку.", "未找到 Steam 启动程序。请先启动一次 Steam，然后重试。", "Steam の起動プログラムが見つかりません。一度 Steam を起動してから再試行してください。"),
})

# BEGIN EMBEDDED RECOMMENDATIONS
EMBEDDED_RECOMMENDATIONS = 'https://github.com/Steamdeckchecker/SDC-Benchmark-\nhttps://github.com/Steamdeckchecker/TrailerHero-SteamOS-Bazzite-\nhttps://github.com/Steamdeckchecker/Steam-Deck-Checker-Video-Checker\nhttps://github.com/Ciphay/Decky-File-Manager\nhttps://github.com/BrenticusMaximus/ThemeDeck\nhttps://github.com/Hooandee/panel-de-control\nhttps://github.com/eugeniosegala/MAKO\nhttps://github.com/LoZazaMastro/Quick-Settings\nhttps://github.com/LoZazaMastro/Shortcuts\nhttps://github.com/Steamdeckchecker/Github-Decky-Plugins-Updater\nhttps://github.com/Steamdeckchecker/Quest-Compendium-Decky\nhttps://github.com/PeroTuncay/DeckyHelixSRManager\nhttps://github.com/xXJSONDeruloXx/decky-lsfg-vk\nhttps://github.com/xXJSONDeruloXx/Decky-Framegen\nhttps://github.com/mubaraknumann/unifideck\nhttps://github.com/SteamGridDB/decky-steamgriddb\nhttps://github.com/DeckThemes/SDH-CssLoader\nhttps://github.com/cat-in-a-box/Decky-Translator\nhttps://github.com/TheLogicMaster/SDH-AnimationChanger\nhttps://github.com/hulkrelax/hltb-for-deck\nhttps://github.com/jurassicplayer/decky-autoflatpaks\nhttps://github.com/DeckThemes/SDH-AudioLoader\nhttps://github.com/FlashyReese/decky-wine-cellar\n'
# END EMBEDDED RECOMMENDATIONS


class Translator:
    def __init__(self, lang="de"):
        self.lang = lang if lang in LANGUAGES else "en"

    def __call__(self, key, **values):
        return TEXT[key][self.lang].format(**values)


VIDEO_REPOS = {
    "lcd": ("Steam Deck LCD", "Steamdeckchecker/SVSDLCD"),
    "oled": ("Steam Deck OLED", "Steamdeckchecker/SVSDOLED"),
    "machine": ("Steam Machine", "Steamdeckchecker/SVSM"),
    "claw": ("MSI Claw", "Steamdeckchecker/SVMSICLAW"),
    "legion": ("Legion Go 2", "Steamdeckchecker/SVLLGO"),
    "other": ("other", "Steamdeckchecker/SVOTHER"),
}

# Name, application ID, localized description, remote. All apps use user Flatpaks.
APPS = [
    ("Heroic", "com.heroicgameslauncher.hgl", L("Epic, GOG and Amazon game launcher", "Launcher für Epic, GOG und Amazon", "Lanzador para Epic, GOG y Amazon", "Lanceur Epic, GOG et Amazon", "Лаунчер Epic, GOG и Amazon", "Epic、GOG 和 Amazon 游戏启动器", "Epic・GOG・Amazon 用ランチャー"), "flathub"),
    ("ProtonUp-Qt", "net.davidotek.pupgui2", L("Install and manage GE-Proton and compatibility tools", "GE-Proton und Kompatibilitätswerkzeuge verwalten", "Gestiona GE-Proton y herramientas de compatibilidad", "Gérer GE-Proton et les outils de compatibilité", "Управление GE-Proton и средствами совместимости", "安装和管理 GE-Proton 及兼容工具", "GE-Proton と互換ツールの管理"), "flathub"),
    ("Proton Plus", "com.vysp3r.ProtonPlus", L("Manage Proton and Wine compatibility versions", "Proton- und Wine-Versionen verwalten", "Gestiona versiones de Proton y Wine", "Gérer les versions de Proton et Wine", "Управление версиями Proton и Wine", "管理 Proton 和 Wine 兼容版本", "Proton・Wine のバージョン管理"), "flathub"),
    ("VacuumTube", "rocks.shy.VacuumTube", L("YouTube TV interface for the desktop", "YouTube-TV-Oberfläche für den Desktop", "Interfaz de YouTube TV para escritorio", "Interface YouTube TV pour le bureau", "ТВ-интерфейс YouTube для рабочего стола", "桌面版 YouTube 电视界面", "デスクトップ向け YouTube TV インターフェース"), "flathub"),
    ("Lutris", "net.lutris.Lutris", L("Manage games from multiple sources", "Spiele aus verschiedenen Quellen verwalten", "Gestiona juegos de varias fuentes", "Gérer les jeux de différentes sources", "Управление играми из разных источников", "管理多个来源的游戏", "複数サービスのゲームを管理"), "flathub"),
    ("Moonlight", "com.moonlight_stream.Moonlight", L("Stream games from a PC running Sunshine", "PC-Spiele über Sunshine streamen", "Transmite juegos desde un PC con Sunshine", "Diffuser les jeux d'un PC avec Sunshine", "Трансляция игр с ПК через Sunshine", "通过 Sunshine 串流电脑游戏", "Sunshine 搭載 PC からゲームを配信"), "flathub"),
    ("Chiaki4deck", "io.github.streetpea.Chiaki4deck", L("PlayStation Remote Play (chiaki-ng)", "PlayStation Remote Play (chiaki-ng)", "Juego remoto de PlayStation (chiaki-ng)", "Lecture à distance PlayStation (chiaki-ng)", "Удалённая игра PlayStation (chiaki-ng)", "PlayStation 远程游玩（chiaki-ng）", "PlayStation リモートプレイ（chiaki-ng）"), "flathub"),
    ("GeForce NOW", "com.nvidia.geforcenow", L("NVIDIA's official cloud gaming client", "Offizieller Cloud-Gaming-Client von NVIDIA", "Cliente oficial de juego en la nube de NVIDIA", "Client officiel de cloud gaming NVIDIA", "Официальный клиент облачного гейминга NVIDIA", "NVIDIA 官方云游戏客户端", "NVIDIA 公式クラウドゲームクライアント"), "GeForceNOW"),
    ("XStreaming", "io.github.Geocld.XStreamingDesktop", L("Xbox console streaming", "Streaming von der Xbox-Konsole", "Streaming de consola Xbox", "Streaming de console Xbox", "Трансляция с консоли Xbox", "Xbox 主机串流", "Xbox 本体からのストリーミング"), "flathub"),
    ("Flatseal", "com.github.tchx84.Flatseal", L("Manage Flatpak permissions", "Flatpak-Berechtigungen verwalten", "Gestiona permisos de Flatpak", "Gérer les autorisations Flatpak", "Управление разрешениями Flatpak", "管理 Flatpak 权限", "Flatpak の権限管理"), "flathub"),
    ("Filelight", "org.kde.filelight", L("Find large files and inspect disk usage", "Große Dateien und Speicherbelegung anzeigen", "Analiza el uso del disco y archivos grandes", "Analyser l'espace disque et les gros fichiers", "Анализ занятого места на диске", "分析磁盘使用情况和大文件", "ディスク使用量と大きいファイルを確認"), "flathub"),
    ("Discord", "com.discordapp.Discord", L("Voice chat and community messaging", "Sprachchat und Community-Nachrichten", "Chat de voz y comunidades", "Chat vocal et communautés", "Голосовой чат и сообщества", "语音聊天和社区消息", "ボイスチャットとコミュニティ"), "flathub"),
    ("Google Chrome", "com.google.Chrome", L("Web browser", "Webbrowser", "Navegador web", "Navigateur web", "Веб-браузер", "网页浏览器", "ウェブブラウザー"), "flathub"),
    ("LibreOffice", "org.libreoffice.LibreOffice", L("Documents, spreadsheets and presentations", "Dokumente, Tabellen und Präsentationen", "Documentos, hojas de cálculo y presentaciones", "Documents, tableurs et présentations", "Документы, таблицы и презентации", "文档、电子表格和演示文稿", "文書・表計算・プレゼンテーション"), "flathub"),
    ("SuperTuxKart", "net.supertuxkart.SuperTuxKart", L("Free kart racing game", "Kostenloses Kart-Rennspiel", "Juego gratuito de carreras de karts", "Jeu gratuit de courses de kart", "Бесплатные гонки на картах", "免费卡丁车竞速游戏", "無料のカートレースゲーム"), "flathub"),
    ("Dr. Robotnik's Ring Racers", "org.kartkrew.RingRacers", L("Community-made kart racing game", "Kart-Rennspiel aus der Community", "Juego de karts creado por la comunidad", "Jeu de kart créé par la communauté", "Гонки на картах от сообщества", "社区制作的卡丁车竞速游戏", "コミュニティ制作のカートレースゲーム"), "flathub"),
]


def clean(value, limit=220):
    return re.sub(r"\s+", " ", re.sub(r"[\x00-\x1f\x7f]", " ", str(value))).strip()[:limit]


class Cancelled(Exception):
    pass


class TerminalProgress:
    """Real byte/file progress, or activity with elapsed time when no total is known."""
    def __init__(self, tr=None, stream=None):
        self.tr = tr or Translator("en")
        self.stream = stream if stream is not None else sys.stdout
        self.active = False
        self.label = ""
        self.started = time.monotonic()
        self.last = -1.0
        self.tick = 0

    def start(self, label):
        self.finish()
        self.label = clean(label, 150)
        self.started = time.monotonic()
        self.last = -1.0
        self.stream.write(f"[{dt.datetime.now():%H:%M:%S}] {self.label}\n")
        self.stream.flush()

    def clear(self):
        if self.active:
            self.stream.write("\r\033[2K")
            self.stream.flush()
            self.active = False

    def update(self, current=0, total=None, *, unit="bytes", force=False):
        now = time.monotonic()
        tty = getattr(self.stream, "isatty", lambda: False)()
        if not force and self.last >= 0 and now - self.last < (0.3 if tty else 1.0):
            return
        self.last = now
        elapsed = max(0.0, now - self.started)
        clock = f"{int(elapsed)//60:02d}:{int(elapsed)%60:02d}"
        if total is not None and total > 0:
            ratio = min(1.0, max(0.0, current / total))
            filled = int(22 * ratio)
            bar = "[" + "=" * filled + "." * (22 - filled) + "]"
            status = f"{bar} {ratio:6.1%}"
        else:
            spinner = "|/-\\"[self.tick % 4]
            self.tick += 1
            status = f"[{spinner}]"
        if unit == "bytes":
            amount = f"{current/1024**2:.1f} MiB"
            if total:
                amount = f"{current/1024**2:.1f}/{total/1024**2:.1f} MiB"
            speed = f"  {current/1024**2/max(elapsed,0.01):.1f} MiB/s" if current else ""
            status += "  " + amount + speed
        elif unit == "files":
            status += f"  {current}" + (f"/{total}" if total else "") + " " + self.tr("files_unit")
        status += "  " + clock
        if tty:
            self.stream.write("\r\033[2K" + status)
            self.active = True
        else:
            self.stream.write(f"[{dt.datetime.now():%H:%M:%S}] {self.label}: {status}\n")
        self.stream.flush()

    def finish(self):
        if self.active:
            self.stream.write("\n")
            self.stream.flush()
            self.active = False


class ProgressLogHandler(logging.StreamHandler):
    def __init__(self, progress):
        super().__init__(progress.stream)
        self.progress = progress

    def emit(self, record):
        self.progress.clear()
        super().emit(record)


class Gui:
    """Native desktop dialogs. Neither a browser nor tkinter is required."""
    def __init__(self, tr):
        self.tr = tr
        self.backend = "zenity" if shutil.which("zenity") else "kdialog" if shutil.which("kdialog") else None
        if not self.backend or not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
            raise RuntimeError(tr("no_gui"))

    def call(self, args):
        p = subprocess.run([self.backend, *args], capture_output=True, text=True)
        if p.returncode not in (0, 1):
            raise RuntimeError(clean(p.stderr, 800) or f"{self.backend}: {p.returncode}")
        return p.returncode == 0, p.stdout.rstrip("\n")

    def title(self, title):
        return ["--title", f"Linux Handheld Starter Kit · {title}"]

    def info(self, title, text, error=False):
        if self.backend == "zenity":
            self.call(self.title(title) + ["--error" if error else "--info", "--no-markup", "--width=620", "--text", text, "--ok-label", self.tr("next")])
        else:
            self.call(self.title(title) + ["--error" if error else "--msgbox", text])

    def question(self, title, text):
        if self.backend == "zenity":
            args = ["--question", "--no-markup", "--width=650", "--text", text, "--ok-label", self.tr("yes"), "--cancel-label", self.tr("no")]
        else:
            args = ["--yesno", text, "--yes-label", self.tr("yes"), "--no-label", self.tr("no")]
        return self.call(self.title(title) + args)[0]

    def entry(self, title, text, password=False):
        if self.backend == "zenity":
            args = ["--password" if password else "--entry", "--width=620", "--text", text, "--ok-label", self.tr("next"), "--cancel-label", self.tr("cancel")]
        else:
            args = ["--password" if password else "--inputbox", text]
        ok, value = self.call(self.title(title) + args)
        return value if ok else None

    def file(self, title):
        args = ["--file-selection"] if self.backend == "zenity" else ["--getopenfilename", str(Path.home()), "*.txt"]
        ok, value = self.call(self.title(title) + args)
        return Path(value) if ok and value else None

    def choose(self, title, text, rows, default=None, multiple=False, selected=()):
        if self.backend == "zenity":
            args = ["--list", "--checklist" if multiple else "--radiolist", "--width=1000", "--height=610", "--text", text,
                    "--column", self.tr("select"), "--column=ID", "--column", self.tr("name"), "--column", self.tr("description"),
                    "--hide-column=2", "--print-column=2", "--separator=\n", "--ok-label", self.tr("next"), "--cancel-label", self.tr("cancel")]
            for key, name, desc in rows:
                args += ["TRUE" if (key in selected if multiple else key == default) else "FALSE", str(key), clean(name), clean(desc)]
        else:
            args = ["--separate-output", "--checklist" if multiple else "--radiolist", text]
            for key, name, desc in rows:
                args += [str(key), clean(name) + (" — " + clean(desc) if desc else ""), "on" if (key in selected if multiple else key == default) else "off"]
        ok, value = self.call(self.title(title) + args)
        if not ok:
            return None
        values = value.splitlines() if value else []
        # Older KDialog versions quote single-selection tags.
        values = [x[1:-1] if len(x) >= 2 and x[0] == x[-1] == '"' else x for x in values]
        if multiple:
            return values
        return values[0] if values else None

    @contextlib.contextmanager
    def busy(self, title):
        progress = None
        bus = None
        qdbus = shutil.which("qdbus6") or shutil.which("qdbus") or shutil.which("qdbus-qt6")
        try:
            if self.backend == "zenity":
                progress = subprocess.Popen(["zenity", *self.title(title), "--progress", "--pulsate", "--auto-close", "--no-cancel", "--no-markup", "--width=600", "--text", self.tr("working")], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            elif qdbus:
                ok, value = self.call(self.title(title) + ["--progressbar", self.tr("working"), "0"])
                if ok and len(value.split()) == 2:
                    bus = value.split()
            print(f"[{title}] {self.tr('working')}", flush=True)
            yield
        finally:
            if progress is not None:
                if progress.stdin:
                    with contextlib.suppress(BrokenPipeError):
                        progress.stdin.close()
                try:
                    progress.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    progress.terminate()
                    progress.wait()
            if bus:
                subprocess.run([qdbus, *bus, "org.kde.kdialog.ProgressDialog.close"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def https_url(url):
    u = urllib.parse.urlsplit(url)
    if u.scheme != "https" or not u.hostname or u.username or u.password:
        raise ValueError("Only HTTPS download URLs without embedded credentials are accepted")
    return url


class Network:
    def __init__(self, logger, progress=None):
        self.log = logger
        self.progress = progress or TerminalProgress()
        self.releases_cache = {}
        self.latest_cache = {}

    def open(self, url):
        https_url(url)
        # Redirect handlers must not downgrade HTTPS to unencrypted HTTP.
        class Redirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                https_url(newurl)
                redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
                if redirected and urllib.parse.urlsplit(req.full_url).hostname != urllib.parse.urlsplit(newurl).hostname:
                    redirected.remove_header("Authorization")
                return redirected
        headers = {"User-Agent": f"LinuxHandheldStarterKit/{VERSION}", "Accept": "application/vnd.github+json" if url.startswith("https://api.github.com/") else "*/*"}
        token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
        if token and urllib.parse.urlsplit(url).hostname == "api.github.com":
            headers["Authorization"] = "Bearer " + token
            if "/releases/assets/" in url:
                headers["Accept"] = "application/octet-stream"
        req = urllib.request.Request(url, headers=headers)
        return urllib.request.build_opener(Redirect()).open(req, timeout=60)

    def download(self, url, destination, digest=None, limit=4 * 1024**3):
        destination = Path(destination)
        part = destination.with_name(destination.name + ".part")
        self.log.info("Download %s", url)
        for attempt in range(3):
            self.progress.start(self.progress.tr("transfer", name=destination.name))
            try:
                sha = hashlib.sha256()
                size = 0
                with self.open(url) as response, part.open("wb") as output:
                    length = int(response.headers.get("Content-Length", 0))
                    if length > limit:
                        raise ValueError("Download exceeds size limit")
                    self.progress.update(0, length or None, force=True)
                    while True:
                        chunk = response.read(1024 * 1024)
                        if not chunk:
                            break
                        size += len(chunk)
                        if size > limit:
                            raise ValueError("Download exceeds size limit")
                        output.write(chunk)
                        sha.update(chunk)
                        self.progress.update(size, length or None)
                    if length and length != size:
                        raise ValueError("Incomplete download")
                self.progress.finish()
                self.log.info(self.progress.tr("verify_download"))
                if not size:
                    raise ValueError("Empty download")
                if digest and sha.hexdigest().lower() != digest.removeprefix("sha256:").lower():
                    raise ValueError("SHA-256 mismatch")
                os.replace(part, destination)
                self.progress.update(size, size, force=True)
                self.progress.finish()
                return destination
            except (OSError, ValueError, urllib.error.URLError) as exc:
                self.progress.finish()
                part.unlink(missing_ok=True)
                self.log.warning("Download attempt %s: %s", attempt + 1, exc)
                if attempt == 2 or isinstance(exc, urllib.error.HTTPError) and exc.code in (403, 404, 429):
                    raise
                time.sleep(attempt + 1)

    def json(self, url, optional=False, limit=16 * 1024**2):
        self.log.info(self.progress.tr("checking_source", name=url))
        try:
            with self.open(url) as response:
                data = response.read(limit + 1)
                if len(data) > limit:
                    raise ValueError("JSON document is too large")
                return json.loads(data)
        except urllib.error.HTTPError as exc:
            if optional and exc.code == 404:
                return None
            if exc.code in (403, 429):
                raise RuntimeError("GitHub rate limit or access restriction. Please try again later.") from exc
            raise

    def releases(self, repo):
        repo = normalize_repo(repo)
        if repo not in self.releases_cache:
            data = self.json(f"https://api.github.com/repos/{repo}/releases?per_page=10")
            self.releases_cache[repo] = [x for x in data if not x.get("draft")]
        return self.releases_cache[repo]

    def latest(self, repo):
        repo = normalize_repo(repo)
        if repo not in self.latest_cache:
            stable = self.json(f"https://api.github.com/repos/{repo}/releases/latest", optional=True)
            self.latest_cache[repo] = stable or (self.releases(repo) or [None])[0]
        return self.latest_cache[repo]


def normalize_repo(value):
    value = value.strip()
    if value.startswith("https://github.com/"):
        parts = urllib.parse.urlsplit(value).path.strip("/").split("/")
        if len(parts) < 2:
            raise ValueError(f"Invalid GitHub repository: {value}")
        value = "/".join(parts[:2])
    value = value.removesuffix(".git").rstrip("/")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*/[A-Za-z0-9_.-]+", value) or value.split("/")[1] in (".", ".."):
        raise ValueError(f"Invalid GitHub repository: {value}")
    return value


def parse_recommend(text, source="built-in recommendations"):
    result = []
    for number, raw in enumerate(text.lstrip("\ufeff").splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = [x.strip() for x in line.split("|", 1)]
        try:
            repo = normalize_repo(parts[0])
        except ValueError as exc:
            raise ValueError(f"{source}:{number}: {exc}") from exc
        if repo.casefold() not in {x[0].casefold() for x in result}:
            result.append((repo, parts[1] if len(parts) > 1 else ""))
    return result


def read_recommend(path):
    return parse_recommend(Path(path).read_text(encoding="utf-8-sig"), str(path))


def safe_member(name):
    p = PurePosixPath(name)
    if not name or "\\" in name or p.is_absolute() or ".." in p.parts or any(":" in x or "\x00" in x for x in p.parts):
        raise ValueError(f"Unsafe archive member: {name}")
    return p


def extract_archive(archive, destination, limit=8 * 1024**3, progress=None):
    """Never extract symlinks, device nodes or traversal paths; preserve executable bits."""
    archive, destination = Path(archive), Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    size = 0
    count = 0
    seen = set()
    progress = progress or TerminalProgress()
    progress.start(progress.tr("extracting", name=archive.name))
    extracted = 0

    def copy_content(src, dst, total):
        nonlocal extracted
        while True:
            chunk = src.read(1024 * 1024)
            if not chunk:
                break
            dst.write(chunk)
            extracted += len(chunk)
            progress.update(extracted, total)

    def target(name, length):
        nonlocal size, count
        relative = safe_member(name)
        if str(relative) in seen:
            raise ValueError(f"Duplicate archive member: {name}")
        seen.add(str(relative))
        size += length
        count += 1
        if size > limit or count > 50000:
            raise ValueError("Archive exceeds extraction limits")
        out = destination.joinpath(*relative.parts)
        if not out.resolve().is_relative_to(destination.resolve()):
            raise ValueError("Archive escapes destination")
        return out

    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as z:
            total = sum(info.file_size for info in z.infolist())
            progress.update(0, total or None, force=True)
            for info in z.infolist():
                out = target(info.filename, info.file_size)
                mode = info.external_attr >> 16
                if stat.S_ISLNK(mode) or stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR):
                    raise ValueError("Archive contains a link or special file")
                if info.is_dir():
                    out.mkdir(parents=True, exist_ok=True)
                else:
                    out.parent.mkdir(parents=True, exist_ok=True)
                    with z.open(info) as src, out.open("wb") as dst:
                        copy_content(src, dst, total or None)
                    out.chmod(0o755 if mode & 0o111 else 0o644)
    elif tarfile.is_tarfile(archive):
        with tarfile.open(archive) as tar:
            for info in tar:
                out = target(info.name, info.size)
                if info.isdir():
                    out.mkdir(parents=True, exist_ok=True)
                elif info.isfile():
                    out.parent.mkdir(parents=True, exist_ok=True)
                    with tar.extractfile(info) as src, out.open("wb") as dst:
                        copy_content(src, dst, None)
                    out.chmod(0o755 if info.mode & 0o111 else 0o644)
                else:
                    raise ValueError("Archive contains a link or special file")
    else:
        raise ValueError("Not a ZIP or tar archive")
    progress.update(extracted, extracted or 1, force=True)
    progress.finish()
    return destination


def is_archive(name):
    return str(name).lower().endswith((".zip", ".tar.gz", ".tgz"))


def find_video_files(directory, depth=0, progress=None):
    files = [p for p in Path(directory).rglob("*") if p.is_file() and p.suffix.lower() == ".webm" and "__MACOSX" not in p.parts and not p.name.startswith("._")]
    if files or depth >= 2:
        return sorted(files)
    for path in list(Path(directory).rglob("*")):
        if path.is_file() and is_archive(path.name):
            nested = path.parent / (path.name + ".unpacked")
            extract_archive(path, nested, progress=progress)
            files.extend(find_video_files(nested, depth + 1, progress=progress))
    return sorted(files)


def discover_steam(home):
    home = Path(home)
    candidates = [home / ".steam/root", home / ".steam/steam", home / ".local/share/Steam", home / ".var/app/com.valvesoftware.Steam/.local/share/Steam", home / ".var/app/com.valvesoftware.Steam/data/Steam"]
    return next((p.resolve() for p in candidates if p.is_dir() and any((p / x).exists() for x in ("steam.sh", "steamapps", "userdata", "config"))), None)


def read_os_release(path="/etc/os-release"):
    result = {}
    try:
        for line in Path(path).read_text().splitlines():
            if "=" in line and not line.startswith("#"):
                key, value = line.split("=", 1)
                result[key] = value.strip().strip('"')
    except OSError:
        pass
    return result


class Runner:
    def __init__(self, log, dry=False, progress=None):
        self.log, self.dry = log, dry
        self.progress = progress or TerminalProgress()

    def run(self, args, *, check=True, timeout=None, env=None, capture=True):
        self.log.info("Command: %s", shlex.join([str(x) for x in args]))
        if self.dry:
            return subprocess.CompletedProcess(args, 0, "", "")
        if capture:
            self.progress.start(self.progress.tr("executing", name=Path(str(args[0])).name))
            started = time.monotonic()
            tail = ""
            pending = ""
            decoder = codecs.getincrementaldecoder("utf-8")("replace")
            with subprocess.Popen([str(x) for x in args], stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, bufsize=0, env=env) as process:
                selector = selectors.DefaultSelector()
                selector.register(process.stdout, selectors.EVENT_READ)
                try:
                    while selector.get_map() or process.poll() is None:
                        if timeout is not None and time.monotonic() - started > timeout:
                            raise subprocess.TimeoutExpired(args, timeout, output=tail)
                        for key, _ in selector.select(0.25):
                            data = os.read(key.fileobj.fileno(), 65536)
                            if not data:
                                selector.unregister(key.fileobj)
                                key.fileobj.close()
                                continue
                            text = decoder.decode(data)
                            tail = (tail + text)[-512 * 1024:]
                            pending += text.replace("\r", "\n")
                            lines = pending.split("\n")
                            pending = lines.pop()
                            for line in lines:
                                if line:
                                    self.log.info("%s", line)
                            # Flush very long non-newline output as well.
                            if len(pending) > 8192:
                                self.log.info("%s", pending)
                                pending = ""
                        self.progress.update(unit="time")
                    pending += decoder.decode(b"", final=True)
                    if pending:
                        self.log.info("%s", pending)
                    p = subprocess.CompletedProcess(args, process.wait(), tail, None)
                except BaseException:
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
                    raise
                finally:
                    selector.close()
                    self.progress.finish()
        else:
            p = subprocess.run([str(x) for x in args], timeout=timeout, env=env)
        if check and p.returncode:
            raise RuntimeError(f"{Path(str(args[0])).name}: exit {p.returncode}\n{clean(p.stdout or '', 1500)}")
        return p


class Sudo:
    def __init__(self, ui, runner, work):
        self.ui, self.runner, self.work = ui, runner, Path(work)
        self.authorized = False
        self.stop_event = threading.Event()
        self.thread = None

    def password_status(self):
        if not shutil.which("passwd"):
            return "UNKNOWN"
        p = subprocess.run(["passwd", "-S"], capture_output=True, text=True, env={**os.environ, "LC_ALL": "C"})
        fields = p.stdout.split()
        return fields[1] if p.returncode == 0 and len(fields) > 1 else "UNKNOWN"

    def create_password(self):
        terminal = next((x for x in ("konsole", "gnome-terminal", "xterm") if shutil.which(x)), None)
        if terminal is None:
            raise RuntimeError(self.ui.tr("terminal_missing"))
        status_file = self.work / "passwd-result"
        script = self.work / "set-password.sh"
        # The native passwd tool owns password entry. No password goes in a file or command line.
        script.write_text("#!/bin/bash\npasswd\nresult=$?\nprintf '%s' \"$result\" > " + shlex.quote(str(status_file)) + "\nexit \"$result\"\n")
        script.chmod(0o700)
        args = {"konsole": ["konsole", "--separate", "--nofork", "-e", "bash", str(script)],
                "gnome-terminal": ["gnome-terminal", "--wait", "--", "bash", str(script)],
                "xterm": ["xterm", "-e", "bash", str(script)]}[terminal]
        self.runner.run(args, check=False, capture=False)
        if not status_file.exists() or status_file.read_text().strip() != "0":
            raise RuntimeError("passwd did not complete successfully")

    def authenticate(self, force=False):
        if self.runner.dry:
            self.authorized = True
            return True
        if not shutil.which("sudo"):
            return False
        if not force and self.authorized and subprocess.run(["sudo", "-n", "-v"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
            return True
        while True:
            password = self.ui.entry(self.ui.tr("auth"), self.ui.tr("auth_text"), password=True)
            if password is None:
                self.authorized = False
                return False
            # Reset separately: combining -k with -v validates the password but
            # does not cache a timestamp, so the later sudo -n commands fail.
            # stdin only: never log or retain the password for later operations.
            self.authorized = False
            try:
                subprocess.run(["sudo", "-k"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                proc = subprocess.run(["sudo", "-S", "-p", "", "-v"], input=password + "\n", text=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            finally:
                del password
            if proc.returncode == 0:
                self.authorized = True
                if self.thread is None:
                    self.thread = threading.Thread(target=self._keepalive, daemon=True)
                    self.thread.start()
                return True
            if not self.ui.question(self.ui.tr("auth"), self.ui.tr("auth_failed")):
                self.authorized = False
                return False

    def _keepalive(self):
        while not self.stop_event.wait(40):
            subprocess.run(["sudo", "-n", "-v"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def run(self, args, **kwargs):
        if not self.authenticate():
            raise RuntimeError(self.ui.tr("no_admin"))
        return self.runner.run(["sudo", "-n", *args], **kwargs)

    def close(self):
        self.stop_event.set()
        if self.thread:
            self.thread.join(timeout=3)
        if self.authorized and not self.runner.dry:
            subprocess.run(["sudo", "-k"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def parse_binary_vdf(data):
    """Keep leaf bytes and field order, including fields this installer does not edit."""
    if len(data) > 32 * 1024**2:
        raise ValueError("Steam shortcuts file exceeds size limit")
    pos = 0

    def take(size):
        nonlocal pos
        if pos + size > len(data):
            raise ValueError("Truncated Steam shortcuts file")
        result = data[pos:pos + size]
        pos += size
        return result

    def string():
        nonlocal pos
        end = data.find(b"\0", pos)
        if end < 0:
            raise ValueError("Invalid VDF string")
        result = data[pos:end]
        pos = end + 1
        return result

    def obj(depth=0):
        if depth > 32:
            raise ValueError("VDF nesting is too deep")
        fields = []
        while True:
            kind = take(1)[0]
            if kind == 8:
                return fields
            key = string()
            if kind == 0:
                value = obj(depth + 1)
            elif kind == 1:
                value = string()
            elif kind in (2, 3, 4, 6):
                value = take(4)
            elif kind in (7, 10):
                value = take(8)
            elif kind == 5:
                # Binary KeyValues wide strings: uint16 character count, followed by UTF-16.
                length = take(2)
                value = length + take(struct.unpack("<H", length)[0] * 2)
            else:
                raise ValueError(f"Unsupported VDF field type {kind}; original file left intact")
            fields.append([kind, key, value])
    result = obj()
    if pos != len(data):
        raise ValueError("Unexpected trailing VDF data; original file left intact")
    return result


def dump_binary_vdf(fields):
    out = bytearray()
    for kind, key, value in fields:
        out += bytes([kind]) + key + b"\0"
        out += dump_binary_vdf(value) if kind == 0 else value + (b"\0" if kind == 1 else b"")
    return bytes(out) + b"\x08"


def vdf_get(fields, key, default=None):
    key = key.lower().encode()
    return next((value for _, name, value in fields if name.lower() == key), default)


def steam_quote(value):
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def make_command_shortcut(name, executable, directory, launch_options="", flatpak_id="", appimage_path=""):
    exe = steam_quote(executable)
    number = (zlib.crc32((exe + name).encode("utf-8")) | 0x80000000) & 0xFFFFFFFF
    def s(key, value):
        return [1, key.encode(), value.encode("utf-8")]
    def i(key, value):
        return [2, key.encode(), struct.pack("<I", value)]
    fields = [i("appid", number), s("AppName", name), s("Exe", exe), s("StartDir", steam_quote(directory)),
            s("icon", ""), s("ShortcutPath", ""), s("LaunchOptions", launch_options),
            i("IsHidden", 0), i("AllowDesktopConfig", 1), i("AllowOverlay", 1), i("OpenVR", 0),
            i("Devkit", 0), s("DevkitGameID", ""), i("DevkitOverrideAppID", 0), i("LastPlayTime", 0),
            s("FlatpakAppID", flatpak_id), [0, b"tags", [s("0", "Linux Handheld Starter Kit")]]]
    if appimage_path:
        fields.append(s("StarterKitAppImagePath", str(appimage_path)))
    return fields


def make_shortcut(name, appid, home, flatpak):
    return make_command_shortcut(name, flatpak, home, "run " + appid, flatpak_id=appid)


def make_appimage_shortcut(name, path, env_executable="/usr/bin/env"):
    # Launch through env so EmuDeck also works on hosts without FUSE.
    path = Path(path)
    return make_command_shortcut(name, env_executable, path.parent,
                                 "APPIMAGE_EXTRACT_AND_RUN=1 " + steam_quote(path), appimage_path=path)


def merge_shortcuts(original, apps, home, flatpak, appimages=(), env_executable="/usr/bin/env"):
    root = parse_binary_vdf(original) if original else [[0, b"shortcuts", []]]
    entries = vdf_get(root, "shortcuts")
    if not isinstance(entries, list):
        raise ValueError("Invalid shortcuts root; original file left intact")
    if any(kind != 0 or not key.isdigit() for kind, key, _ in entries):
        raise ValueError("Unexpected shortcuts entries; original file left intact")
    installed = set()
    installed_appimages = set()
    for _, _, fields in entries:
        existing_id = vdf_get(fields, "FlatpakAppID", b"").decode("utf-8", "replace")
        if existing_id:
            installed.add(existing_id)
        launch = vdf_get(fields, "LaunchOptions", b"").decode("utf-8", "replace")
        executable = vdf_get(fields, "Exe", b"").decode("utf-8", "replace")
        native_path = vdf_get(fields, "StarterKitAppImagePath", b"").decode("utf-8", "replace")
        if native_path:
            installed_appimages.add(native_path)
        # Recognize existing shortcuts created by other tools as well.
        command = executable + " " + launch
        if "flatpak" in command:
            installed.update(re.findall(r"(?<![\w.])(?:[A-Za-z0-9_-]+\.){2,}[A-Za-z0-9_-]+(?![\w.])", command))
        try:
            arguments = shlex.split(command)
        except ValueError:
            arguments = []
        for _, path in appimages:
            if str(path) in arguments:
                installed_appimages.add(str(path))
    index = max((int(key) for _, key, _ in entries), default=-1) + 1
    for name, appid in apps:
        if appid not in installed:
            entries.append([0, str(index).encode(), make_shortcut(name, appid, home, flatpak)])
            index += 1
            installed.add(appid)
    for name, path in appimages:
        if str(path) not in installed_appimages:
            entries.append([0, str(index).encode(), make_appimage_shortcut(name, path, env_executable)])
            index += 1
            installed_appimages.add(str(path))
    return dump_binary_vdf(root)


def steam_running(uid=None):
    uid = os.getuid() if uid is None else uid
    for proc in Path("/proc").iterdir():
        if proc.name.isdigit():
            try:
                if proc.stat().st_uid == uid and (proc / "comm").read_text().strip() in ("steam", "steamwebhelper"):
                    return True
            except (OSError, ProcessLookupError):
                pass
    return False


def atomic_write(path, data, mode=0o600):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temporary)


def apply_plugin(manifest_path):
    """Narrow privileged file operation; all downloading/validation happens as the user."""
    if os.geteuid() != 0 or not os.environ.get("SUDO_USER"):
        raise RuntimeError("Plugin deployment requires sudo")
    account = pwd.getpwnam(os.environ["SUDO_USER"])
    home = Path(account.pw_dir).resolve()
    manifest = json.loads(Path(manifest_path).read_text())
    source = Path(manifest["source"]).resolve()
    metadata = json.loads((source / "plugin.json").read_text())
    if not (source / "dist/index.js").is_file() or not metadata.get("name"):
        raise ValueError("Invalid prepared plugin")
    base = home / "homebrew/plugins"
    if base.is_symlink() or (home / "homebrew").is_symlink():
        raise ValueError("Symlinked Decky directories require manual installation")
    base.mkdir(parents=True, exist_ok=True)
    for file in source.rglob("*"):
        if file.is_symlink() or not (file.is_file() or file.is_dir()):
            raise ValueError("Prepared plugin contains a link or special file")
    folder = manifest["folder"]
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_. -]{0,140}", folder) or folder in (".", ".."):
        raise ValueError("Invalid plugin folder name")
    # Keep the folder of an installed plugin with the same plugin.json name.
    for old in base.iterdir():
        if old.is_symlink():
            continue
        try:
            if json.loads((old / "plugin.json").read_text()).get("name") == metadata["name"]:
                folder = old.name
                break
        except (OSError, ValueError):
            continue
    target = base / folder
    if target.is_symlink():
        raise ValueError("Plugin destination is a symlink")
    if target.exists():
        try:
            existing_name = json.loads((target / "plugin.json").read_text())["name"]
        except (OSError, ValueError, KeyError) as exc:
            raise ValueError("Existing destination is not a recognized plugin") from exc
        if existing_name != metadata["name"]:
            raise ValueError("Destination belongs to a different plugin")
    staging = base / (".starterkit-" + uuid.uuid4().hex)
    backup = None
    try:
        shutil.copytree(source, staging)
        root_plugin = "root" in metadata.get("flags", [])
        uid, gid = (0, 0) if root_plugin else (account.pw_uid, account.pw_gid)
        for item in [staging, *staging.rglob("*")]:
            os.chown(item, uid, gid)
        os.chown(staging, 0, 0)
        staging.chmod(0o755)
        os.chown(staging / "plugin.json", 0, 0)
        (staging / "plugin.json").chmod(0o755)
        if target.exists():
            backup = home / "homebrew/.starter-kit-backups" / (dt.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6]) / folder
            backup.parent.mkdir(parents=True, exist_ok=True)
            os.rename(target, backup)
        try:
            os.rename(staging, target)
        except BaseException:
            if backup and backup.exists() and not target.exists():
                os.rename(backup, target)
            raise
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    # New plugins are also picked up by the loader scan. Preserve its existing display order.
    settings = home / "homebrew/settings/loader.json"
    if settings.exists() and not settings.is_symlink():
        try:
            content = json.loads(settings.read_text())
            order = content.get("pluginOrder", [])
            if isinstance(order, list) and metadata["name"] not in order:
                order.append(metadata["name"])
                content["pluginOrder"] = order
                mode, uid, gid = stat.S_IMODE(settings.stat().st_mode), settings.stat().st_uid, settings.stat().st_gid
                shutil.copy2(settings, settings.with_name("loader.json.starter-kit-backup"))
                atomic_write(settings, json.dumps(content, ensure_ascii=False, indent=2).encode(), mode)
                os.chown(settings, uid, gid)
        except (OSError, ValueError) as exc:
            print(f"Plugin installed; display-order update skipped: {exc}")
    print(f"Installed {metadata['name']} -> {target}")
    if backup:
        print(f"Backup: {backup}")


class Wizard:
    def __init__(self, ui, home, base, work, log, log_path, dry=False, recommend=None, progress=None):
        self.ui, self.tr = ui, ui.tr
        self.home, self.base, self.work = Path(home), Path(base), Path(work)
        self.log, self.log_path, self.dry = log, log_path, dry
        self.progress = progress or TerminalProgress(self.tr)
        self.runner = Runner(log, dry, self.progress)
        self.sudo = Sudo(ui, self.runner, self.work)
        self.network = Network(log, self.progress)
        self.recommend = Path(recommend) if recommend else None
        self.steam = discover_steam(self.home)
        self.device = "lcd"
        self.results = []
        self.catalog = None
        self.store = None
        self.store_attempted = False

    def result(self, item, state, detail=""):
        self.results.append({"item": item, "state": state, "detail": str(detail)})
        self.progress.finish()
        self.log.info("%s: %s %s", self.tr("status_" + state), item, detail)

    def attempt(self, item, action):
        try:
            self.log.info("%s — %s", item, self.tr("working"))
            with self.ui.busy(item):
                value = action()
            self.result(item, "ok")
            return True, value
        except Cancelled:
            self.result(item, "skipped")
            return False, None
        except (Exception, KeyboardInterrupt) as exc:
            self.log.exception("Failed: %s", item)
            self.result(item, "failed", exc)
            self.ui.info(item, self.tr("failed", item=item, error=clean(exc, 1600)), error=True)
            return False, None

    def devices(self):
        rows = [(k, self.tr("other") if k == "other" else "Legion Go" if k == "legion" else v[0], "") for k, v in VIDEO_REPOS.items()]
        self.device = self.ui.choose(self.tr("device"), self.tr("device"), rows, default="lcd")
        if self.device not in VIDEO_REPOS:
            raise Cancelled()

    def passwords(self):
        if self.dry:
            self.ui.info(self.tr("password"), self.tr("dry"))
            self.sudo.authorized = True
            return
        status = self.sudo.password_status()
        if status in ("NP", "L", "LK", "UNKNOWN"):
            key = "create_pw" if status == "NP" else "unknown_pw"
            if self.ui.question(self.tr("password"), self.tr(key)):
                self.attempt(self.tr("password"), self.sudo.create_password)
            elif status == "NP":
                self.ui.info(self.tr("auth"), self.tr("no_admin"))
                return
        # Always ask again even if passwd has just set the password.
        if not self.sudo.authenticate(force=True):
            self.ui.info(self.tr("auth"), self.tr("no_admin"))

    def asset_download(self, asset, target):
        token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
        url = asset.get("url") if token and asset.get("url", "").startswith("https://api.github.com/") else asset.get("browser_download_url")
        if not url:
            raise ValueError("Release asset has no download URL")
        digest = asset.get("digest")
        if digest and not digest.startswith("sha256:"):
            digest = None
        return self.network.download(url, target, digest=digest)

    def install_videos(self, repo, destination):
        if self.dry:
            self.log.info("SIMULATION: video pack %s -> %s", repo, destination)
            return
        stage = Path(tempfile.mkdtemp(prefix="videos-", dir=self.work))
        release = self.network.latest(repo)
        files = []
        if release:
            for number, asset in enumerate(release.get("assets", [])):
                name = asset.get("name", "")
                if is_archive(name):
                    archive = self.asset_download(asset, stage / f"pack-{number}.archive")
                    extracted = extract_archive(archive, stage / f"pack-{number}", progress=self.progress)
                    files.extend(find_video_files(extracted, progress=self.progress))
                elif name.lower().endswith(".webm"):
                    files.append(self.asset_download(asset, stage / (Path(name).name)))
        if not files:
            archive = self.network.download(f"https://api.github.com/repos/{repo}/zipball", stage / "repository.zip")
            files = find_video_files(extract_archive(archive, stage / "repository", progress=self.progress), progress=self.progress)
        if not files:
            raise RuntimeError(self.tr("no_video_files"))
        # Match Steam's flat movies directory. Later files replace earlier namesakes.
        selected = {file.name: file for file in files}
        destination.mkdir(parents=True, exist_ok=True)
        self.progress.start(self.tr("copy_videos"))
        for index, (name, file) in enumerate(selected.items(), 1):
            target = destination / name
            self.log.info(self.tr("overwrite_video", index=index, total=len(selected), name=name))
            atomic_write(target, file.read_bytes(), 0o644)
            self.progress.update(index, len(selected), unit="files", force=True)
        self.progress.finish()
        self.log.info("Installed %s videos to %s", len(selected), destination)

    def videos(self):
        destination = (self.steam or self.home / ".steam/root") / "config/uioverrides/movies"
        rows = [(key, self.tr("other") if key == "other" else value[0], value[1]) for key, value in VIDEO_REPOS.items()]
        rows.append(("none", self.tr("no_videos"), ""))
        selected = self.ui.choose(self.tr("videos"), self.tr("videos_text", path=destination), rows, default=self.device)
        if not selected or selected == "none":
            self.result(self.tr("videos"), "skipped")
            return
        ok, _ = self.attempt(self.tr("videos"), lambda: self.install_videos(VIDEO_REPOS[selected][1], destination))
        if ok:
            self.ui.info(self.tr("videos"), self.tr("video_done"))

    def decky(self):
        loader = self.home / "homebrew/services/PluginLoader"
        if loader.is_file() and os.access(loader, os.X_OK):
            return self.ui.question(self.tr("decky"), self.tr("decky_exists"))
        if not self.ui.question(self.tr("decky"), self.tr("decky_q")):
            self.result("Decky Loader", "skipped")
            return False
        if not self.sudo.authorized:
            self.ui.info(self.tr("decky"), self.tr("no_admin"))
            self.result("Decky Loader", "skipped", "No administrator authorization")
            return False

        def action():
            if self.dry:
                self.log.info("SIMULATION: install official stable Decky Loader")
                return
            missing = [x for x in ("curl", "jq", "systemctl", "getent") if not shutil.which(x)]
            if missing:
                raise RuntimeError("Required tools missing: " + ", ".join(missing))
            # Download the official CLI script, then execute it synchronously with checked results.
            script = self.network.download("https://raw.githubusercontent.com/SteamDeckHomebrew/decky-installer/main/cli/install_release.sh", self.work / "decky-install.sh", limit=1024**2)
            if not script.read_bytes().startswith(b"#!/"):
                raise ValueError("Decky download is not a shell script")
            # Upstream references .steam/steam. Reuse the detected native Steam root without overwriting anything.
            if not self.steam:
                raise RuntimeError(self.tr("no_steam"))
            compat = self.home / ".steam/steam"
            if not compat.exists() and ".var/app/" not in str(self.steam):
                compat.parent.mkdir(parents=True, exist_ok=True)
                compat.symlink_to(self.steam, target_is_directory=True)
            self.sudo.run(["bash", str(script)], timeout=1800)
            if not loader.is_file() or not os.access(loader, os.X_OK):
                raise RuntimeError("Decky Loader binary is missing or invalid")
            with loader.open("rb") as binary:
                if binary.read(4) != b"\x7fELF":
                    raise RuntimeError("Decky Loader binary is missing or invalid")
            self.runner.run(["systemctl", "is-active", "--quiet", "plugin_loader.service"])
        ok, _ = self.attempt("Decky Loader", action)
        return ok

    def get_catalog(self):
        if self.catalog is None:
            try:
                data = self.network.json("https://safetzahirovic.github.io/decky-plugins-explorer/data/plugins.json")
            except Exception:
                data = self.network.json("https://raw.githubusercontent.com/SafetZahirovic/decky-plugins-explorer/main/data/plugins.json")
            if not isinstance(data, list):
                raise ValueError("Unexpected plugin catalog format")
            self.catalog = []
            for entry in data:
                try:
                    normalize_repo(entry["repo"])
                except (KeyError, TypeError, ValueError):
                    continue
                self.catalog.append(entry)
            self.catalog.sort(key=lambda entry: (-int(entry.get("stars") or 0), entry["repo"].casefold()))
        return self.catalog

    def plugin_description(self, entry):
        plugin = entry.get("plugin") or {}
        return clean((plugin.get("publish") or {}).get("description") or plugin.get("description") or self.tr("no_description"))

    def plugin_selection(self):
        while True:
            choice = self.ui.choose(self.tr("plugins"), self.tr("plugin_q"), [("recommended", self.tr("recommended"), self.tr("builtin_recommendations", count=len(parse_recommend(EMBEDDED_RECOMMENDATIONS)))), ("list", self.tr("from_list"), "Decky Plugins Explorer"), ("none", self.tr("no"), "")], default="recommended")
            if not choice or choice == "none":
                return []
            if choice == "recommended":
                if self.recommend is None:
                    self.log.info(self.tr("use_builtin"))
                    action = lambda: parse_recommend(EMBEDDED_RECOMMENDATIONS)
                else:
                    action = lambda: read_recommend(self.recommend)
                ok, repos = self.attempt(self.tr("recommended"), action)
                if ok and repos:
                    return [(repo, description) for repo, description in repos]
                continue
            ok, catalog = self.attempt("Decky Plugins Explorer", self.get_catalog)
            if not ok:
                continue
            while True:
                query = self.ui.entry(self.tr("plugins"), self.tr("search"))
                if query is None:
                    break
                query = query.casefold().strip()
                filtered = [x for x in catalog if query in (x["repo"] + " " + (x.get("plugin") or {}).get("name", "") + " " + self.plugin_description(x)).casefold()]
                if not filtered:
                    if self.ui.question(self.tr("plugins"), self.tr("no_matches")):
                        continue
                    return []
                rows = [(x["repo"], f"★ {x.get('stars', 0)}  {(x.get('plugin') or {}).get('name') or x['repo']}", x["repo"] + " — " + self.plugin_description(x)) for x in filtered]
                selected = self.ui.choose(self.tr("plugins"), self.tr("plugin_list"), rows, multiple=True)
                if selected is None:
                    continue
                return [(repo, "") for repo in selected]

    def plugin_root(self, extracted, depth=0):
        roots = [p.parent for p in Path(extracted).rglob("plugin.json") if (p.parent / "dist/index.js").is_file() and not any(x in p.parts for x in ("node_modules", "__MACOSX"))]
        if len(roots) == 1:
            return roots[0]
        if len(roots) > 1:
            raise ValueError("Archive contains several plugins; cannot choose automatically")
        if depth < 2:
            for nested in list(Path(extracted).rglob("*")):
                if nested.is_file() and is_archive(nested.name):
                    out = nested.parent / (nested.name + ".unpacked")
                    extract_archive(nested, out, progress=self.progress)
                    root = self.plugin_root(out, depth + 1)
                    if root:
                        return root
        return None

    def store_package(self, repo, stage):
        """Use exact name AND author matches; never install a similarly named unrelated plugin."""
        if not self.store_attempted:
            self.store_attempted = True
            try:
                self.store = self.network.json("https://plugins.deckbrew.xyz/plugins")
            except Exception as exc:
                self.log.warning("Official Decky store unavailable: %s", exc)
                self.store = []
        raw = self.network.json(f"https://api.github.com/repos/{repo}/contents/plugin.json", optional=True)
        if not raw:
            return None
        if raw.get("encoding") == "base64" and raw.get("content"):
            metadata = json.loads(base64.b64decode(raw["content"]))
        elif raw.get("download_url"):
            metadata = self.network.json(raw["download_url"])
        else:
            return None
        name, author = metadata.get("name"), metadata.get("author")
        matches = [x for x in self.store or [] if x.get("name") == name and x.get("author") == author and x.get("versions")]
        if len(matches) != 1:
            return None
        version = max(matches[0]["versions"], key=lambda x: x.get("created", ""))
        # Official store artifacts are content-addressed and verified with SHA-256.
        digest = version["hash"]
        if not re.fullmatch(r"[a-fA-F0-9]{64}", digest):
            raise ValueError("Invalid official store package hash")
        url = version.get("artifact") or f"https://cdn.tzatzikiweeb.moe/file/steam-deck-homebrew/versions/{digest}.zip"
        archive = self.network.download(url, stage / "store.zip", digest=digest)
        return self.plugin_root(extract_archive(archive, stage / "store", progress=self.progress))

    def prepare_plugin(self, repo):
        repo = normalize_repo(repo)
        stage = Path(tempfile.mkdtemp(prefix="plugin-", dir=self.work))
        root = None
        from_source = False
        release = self.network.latest(repo)
        if release:
            assets = [x for x in release.get("assets", []) if is_archive(x.get("name", ""))]
            assets.sort(key=lambda x: ("dependenc" in x["name"].lower(), not x["name"].lower().endswith(".zip"), -int(x.get("size") or 0)))
            for number, asset in enumerate(assets):
                try:
                    archive = self.asset_download(asset, stage / f"release-{number}.archive")
                    root = self.plugin_root(extract_archive(archive, stage / f"release-{number}", progress=self.progress))
                    if root:
                        break
                except Exception as exc:
                    self.log.warning("Unusable plugin asset %s: %s", asset["name"], exc)
        if root is None:
            try:
                root = self.store_package(repo, stage)
            except Exception as exc:
                self.log.warning("No official store package for %s: %s", repo, exc)
        if root is None:
            archive = self.network.download(f"https://api.github.com/repos/{repo}/zipball", stage / "source.zip")
            root = self.plugin_root(extract_archive(archive, stage / "source", progress=self.progress))
            from_source = True
        if root is None:
            raise RuntimeError(self.tr("no_plugin_zip"))
        metadata = json.loads((root / "plugin.json").read_text())
        if not isinstance(metadata.get("name"), str) or not metadata["name"].strip():
            raise ValueError("plugin.json has no valid name")
        package = root / "package.json"
        if package.is_file():
            for binary in json.loads(package.read_text()).get("remote_binary", []):
                filename, url, digest = binary["name"], binary["url"], binary["sha256hash"]
                if filename in (".", "..") or "\\" in filename or Path(filename).name != filename or not re.fullmatch(r"[a-fA-F0-9]{64}", digest):
                    raise ValueError("Invalid remote binary metadata")
                target = root / "bin" / filename
                target.parent.mkdir(parents=True, exist_ok=True)
                self.network.download(url, target, digest=digest)
                target.chmod(0o755)
        folder = root.name
        if from_source or root.name.startswith(("release-", "source", "store")):
            folder = repo.split("/")[1]
        folder = re.sub(r"[^A-Za-z0-9_. -]", "_", folder).lstrip(".") or "plugin"
        manifest = stage / "manifest.json"
        manifest.write_text(json.dumps({"source": str(root), "folder": folder}))
        return manifest

    def install_plugins(self, repos):
        if not repos:
            return
        if not self.ui.question(self.tr("plugins"), self.tr("confirm_plugins", items="\n".join(repo for repo, _ in repos))):
            return
        if not self.sudo.authenticate():
            self.ui.info(self.tr("plugins"), self.tr("no_admin"))
            return
        prepared = []
        for repo, _ in repos:
            if self.dry:
                self.result(repo, "ok", "SIMULATION")
                continue
            ok, manifest = self.attempt(repo, lambda repo=repo: self.prepare_plugin(repo))
            if ok:
                # Preparation is not a completed installation; replace the temporary success record.
                self.results.pop()
                prepared.append((repo, manifest))
        if not prepared:
            return
        stopped = False
        try:
            ok, _ = self.attempt("Decky Loader", lambda: self.sudo.run(["systemctl", "stop", "plugin_loader.service"]))
            if not ok:
                for repo, _ in prepared:
                    self.result(repo, "skipped", "Decky service could not be stopped")
                return
            stopped = True
            for repo, manifest in prepared:
                self.attempt(repo, lambda manifest=manifest: self.sudo.run([sys.executable, str(Path(__file__).resolve()), "--apply-plugin", str(manifest)]))
        finally:
            if stopped:
                def start():
                    self.sudo.run(["systemctl", "start", "plugin_loader.service"])
                    self.runner.run(["systemctl", "is-active", "--quiet", "plugin_loader.service"])
                self.attempt("Decky Loader", start)

    def flatpak_installed(self, appid):
        if self.dry:
            return False
        return any(subprocess.run(["flatpak", "info", scope, appid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0 for scope in ("--user", "--system"))

    def install_app(self, name, appid, remote="flathub"):
        if not self.dry and not shutil.which("flatpak"):
            raise RuntimeError(self.tr("flatpak_missing"))
        if self.flatpak_installed(appid):
            self.log.info("Already installed: %s", appid)
            return
        url = "https://flathub.org/repo/flathub.flatpakrepo" if remote == "flathub" else "https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo"
        self.runner.run(["flatpak", "remote-add", "--user", "--if-not-exists", remote, url], timeout=180)
        self.runner.run(["flatpak", "install", "--user", "--noninteractive", "-y", remote, appid])
        if not self.dry and not self.flatpak_installed(appid):
            raise RuntimeError(f"Flatpak installation could not be verified: {appid}")

    def steam_command(self, steam):
        if ".var/app/com.valvesoftware.Steam/" in str(steam):
            if not shutil.which("flatpak"):
                raise RuntimeError(self.tr("flatpak_missing"))
            return ["flatpak", "run", "com.valvesoftware.Steam"]
        executable = shutil.which("steam")
        if executable:
            return [executable]
        script = Path(steam) / "steam.sh"
        if script.is_file() and os.access(script, os.X_OK):
            return [str(script)]
        raise RuntimeError(self.tr("steam_launcher_missing"))

    def restart_steam(self, command):
        if self.dry:
            self.log.info("SIMULATION: wait 3 seconds and start Steam: %s", command)
            return
        self.log.info(self.tr("steam_restart_wait", seconds=3))
        time.sleep(3)
        # Another application may already have reopened Steam after the write.
        if steam_running():
            return
        self.log.info(self.tr("steam_restarting"))
        self.progress.start(self.tr("steam_restarting"))
        try:
            # Steam owns a long-lived GUI process. Detach it and wait only for
            # startup; waiting for its process exit would block the wizard.
            with self.log_path.open("ab", buffering=0) as output:
                process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=output,
                                           stderr=subprocess.STDOUT, start_new_session=True)
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                if steam_running():
                    return
                code = process.poll()
                if code is not None and code != 0:
                    raise RuntimeError(self.tr("steam_restart_failed"))
                self.progress.update(unit="time")
                time.sleep(0.5)
            raise RuntimeError(self.tr("steam_restart_failed"))
        finally:
            self.progress.finish()

    def steam_shortcuts(self, apps, appimages=()):
        if self.dry:
            self.log.info("SIMULATION: add Steam shortcuts %s %s; wait 3 seconds and restart Steam", apps, appimages)
            return
        if not apps and not appimages:
            return
        for _, path in appimages:
            if not Path(path).is_file() or not os.access(path, os.X_OK):
                raise RuntimeError(f"AppImage is missing or not executable: {path}")
        steam = discover_steam(self.home)
        if steam is None:
            raise RuntimeError(self.tr("no_steam"))
        command = self.steam_command(steam)
        userdata = steam / "userdata"
        profiles = sorted([p for p in userdata.iterdir() if p.is_dir() and p.name.isdigit() and p.name != "0"]) if userdata.exists() else []
        if not profiles:
            raise RuntimeError(self.tr("no_steam"))
        profile = profiles[0]
        if len(profiles) > 1:
            # Display names from Steam's loginusers.vdf; IDs remain the authoritative keys.
            names, recent = {}, None
            logins = steam / "config/loginusers.vdf"
            if logins.is_file():
                content = logins.read_text(errors="replace")
                for steamid, block in re.findall(r'"(\d{17})"\s*\{([^{}]*)\}', content):
                    account_id = str(int(steamid) & 0xFFFFFFFF)
                    name = re.search(r'"PersonaName"\s*"([^"\n]*)"', block, re.I)
                    if name:
                        names[account_id] = name.group(1)
                    if re.search(r'"MostRecent"\s*"1"', block, re.I):
                        recent = account_id
            chosen = self.ui.choose("Steam", self.tr("profile"), [(p.name, names.get(p.name, p.name), p.name) for p in profiles], default=recent or profiles[0].name)
            if chosen is None:
                raise Cancelled()
            profile = next(p for p in profiles if p.name == chosen)
        stopped = False
        try:
            if steam_running():
                if not self.ui.question("Steam", self.tr("close_steam")):
                    raise Cancelled()
                self.runner.run(command + ["-shutdown"], check=False, timeout=30)
                deadline = time.monotonic() + 90
                while steam_running() and time.monotonic() < deadline:
                    time.sleep(0.5)
                if steam_running():
                    raise RuntimeError(self.tr("steam_timeout"))
                stopped = True
            path = profile / "config/shortcuts.vdf"
            if path.is_symlink():
                raise ValueError("Steam shortcuts file is a symlink")
            original = path.read_bytes() if path.exists() else b""
            merged = merge_shortcuts(original, apps, self.home, shutil.which("flatpak") or "/usr/bin/flatpak",
                                     appimages=appimages, env_executable=shutil.which("env") or "/usr/bin/env")
            if steam_running():
                raise RuntimeError(self.tr("steam_timeout"))
            if merged != original:
                if original:
                    backup = path.with_name("shortcuts.vdf.starter-kit-" + dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f") + ".bak")
                    shutil.copy2(path, backup)
                atomic_write(path, merged)
        except Exception:
            # Restore a client that we closed even when saving fails. Preserve
            # the original error if restarting also fails.
            if stopped:
                try:
                    self.restart_steam(command)
                except Exception:
                    self.log.exception("Steam restart after shortcut failure also failed")
            raise
        self.restart_steam(command)

    def offer_steam_shortcuts(self, apps=(), appimages=(), name=None):
        question = self.tr("add_emulation_steam", name=name) if name else self.tr("add_steam")
        if self.ui.question("Steam", question):
            action = (lambda: self.steam_shortcuts(apps, appimages=appimages)) if appimages else (lambda: self.steam_shortcuts(apps))
            ok, _ = self.attempt("Steam", action)
            if ok:
                self.ui.info("Steam", self.tr("steam_done"))

    def applications(self):
        selected = self.ui.choose(self.tr("apps"), self.tr("apps_text"), [(appid, name, desc[self.tr.lang]) for name, appid, desc, _ in APPS], multiple=True)
        if not selected:
            self.result(self.tr("apps"), "skipped")
            return
        successful = []
        for name, appid, _, remote in APPS:
            if appid in selected:
                ok, _ = self.attempt(name, lambda name=name, appid=appid, remote=remote: self.install_app(name, appid, remote))
                if ok:
                    successful.append((name, appid))
        if successful:
            self.offer_steam_shortcuts(successful)

    def install_emudeck(self):
        if self.dry:
            self.log.info("SIMULATION: download and run official EmuDeck AppImage; wait for process exit")
            return self.home / "Applications/EmuDeck.AppImage"
        # This is the same official AppImage launched by EmuDeck.sh. Avoid the bootstrap's
        # automatic full pacman update / rpm-ostree layering on an immutable host.
        release = self.network.latest("EmuDeck/emudeck-electron")
        if not release:
            raise RuntimeError("No official EmuDeck release found")
        assets = [a for a in release.get("assets", []) if a.get("name", "").endswith(".AppImage") and "arm64" not in a["name"].lower() and "aarch64" not in a["name"].lower()]
        if len(assets) != 1:
            raise RuntimeError("Could not identify the x86_64 EmuDeck AppImage")
        target = self.home / "Applications/EmuDeck.AppImage"
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_symlink():
            raise ValueError("EmuDeck destination is a symlink")
        if target.exists():
            shutil.copy2(target, target.with_name("EmuDeck.AppImage.starter-kit-backup"))
        self.asset_download(assets[0], target)
        target.chmod(0o755)
        self.ui.info(self.tr("emulation"), self.tr("emu_wait"))
        # extract-and-run works without installing FUSE or altering the OS image.
        self.runner.run([str(target)], env={**os.environ, "APPIMAGE_EXTRACT_AND_RUN": "1"})
        return target

    def emulation(self):
        choice = self.ui.choose(self.tr("emulation"), self.tr("emu_q"), [("retrodeck", "RetroDECK", self.tr("retro_desc")), ("emudeck", "EmuDeck", self.tr("emu_desc")), ("none", self.tr("no"), "")], default="none")
        if choice == "retrodeck":
            ok, _ = self.attempt("RetroDECK", lambda: self.install_app("RetroDECK", "net.retrodeck.retrodeck"))
            if ok:
                self.offer_steam_shortcuts([("RetroDECK", "net.retrodeck.retrodeck")], name="RetroDECK")
        elif choice == "emudeck":
            ok, target = self.attempt("EmuDeck", self.install_emudeck)
            if ok:
                self.ui.info("EmuDeck", self.tr("finished_emu"))
                self.offer_steam_shortcuts(appimages=[("EmuDeck", target)], name="EmuDeck")
        else:
            self.result(self.tr("emulation"), "skipped")

    def finish(self):
        summary = self.tr("summary", ok=sum(x["state"] == "ok" for x in self.results), failed=sum(x["state"] == "failed" for x in self.results), skipped=sum(x["state"] == "skipped" for x in self.results), log=self.log_path)
        self.ui.info(self.tr("finish"), summary)
        if not self.dry:
            atomic_write(self.log_path.with_suffix(".json"), json.dumps(self.results, ensure_ascii=False, indent=2).encode())
        if self.ui.question(self.tr("finish"), self.tr("reboot")):
            if self.dry:
                self.log.info("SIMULATION: restart")
            else:
                ok, _ = self.attempt(self.tr("reboot"), lambda: self.runner.run(["systemctl", "reboot"], timeout=30))
                if not ok and self.sudo.authorized:
                    self.attempt(self.tr("reboot"), lambda: self.sudo.run(["systemctl", "reboot"], timeout=30))

    def run(self):
        try:
            self.log.info(self.tr("device"))
            self.devices()
            self.log.info(self.tr("password"))
            self.passwords()
            self.log.info(self.tr("videos"))
            self.videos()
            self.log.info(self.tr("decky"))
            if self.decky():
                self.log.info(self.tr("plugins"))
                self.install_plugins(self.plugin_selection())
            self.log.info(self.tr("apps"))
            self.applications()
            self.log.info(self.tr("emulation"))
            self.emulation()
            self.log.info(self.tr("finish"))
            self.finish()
        finally:
            self.sudo.close()


def main(argv=None):
    parser = argparse.ArgumentParser(description="Linux Handheld Starter Kit: SteamOS, CachyOS, Bazzite")
    parser.add_argument("--lang", choices=list(LANGUAGES), help="Preselect a language")
    parser.add_argument("--dry-run", action="store_true", help="Simulate the wizard without installations, password changes or restart")
    parser.add_argument("--check", action="store_true", help="Print local prerequisite information without opening the wizard")
    parser.add_argument("--recommend", type=Path, help="Alternative recommend.txt")
    parser.add_argument("--apply-plugin", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.apply_plugin:
        apply_plugin(args.apply_plugin)
        return 0
    home = Path.home()
    lang = args.lang or os.environ.get("LANG", "en").split("_")[0].split(".")[0]
    tr = Translator(lang)
    if args.check:
        print(json.dumps({"version": VERSION, "os": read_os_release(), "user": pwd.getpwuid(os.getuid()).pw_name, "home": str(home),
                          "steam": str(discover_steam(home) or ""), "tools": {x: shutil.which(x) for x in ("python3", "zenity", "kdialog", "sudo", "passwd", "flatpak", "curl", "jq", "systemctl")},
                          "languages": LANGUAGES, "included_recommendations": len(parse_recommend(EMBEDDED_RECOMMENDATIONS))}, ensure_ascii=False, indent=2))
        return 0
    if os.geteuid() == 0:
        print(tr("root"), file=sys.stderr)
        return 1
    ui = Gui(tr)
    chosen = ui.choose("Language · Sprache · 语言 · 言語", "Deutsch · English · Español · Français · Русский · 中文 · 日本語", [(key, name, "") for key, name in LANGUAGES.items()], default=tr.lang)
    if chosen is None:
        return 0
    tr.lang = chosen
    # One instance per desktop user. The lock and logs live under the writable user home.
    state = home / ".local/state/linux-handheld-starter-kit"
    state.mkdir(parents=True, exist_ok=True)
    lock = (state / "installer.lock").open("a")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        ui.info("Linux Handheld Starter Kit", tr("already_running"), error=True)
        return 1
    log_path = state / ("install-" + dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f") + ".log")
    log_path.touch(mode=0o600)
    logging.basicConfig(filename=log_path, level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", encoding="utf-8")
    logger = logging.getLogger("starterkit")
    logger.setLevel(logging.INFO)
    progress = TerminalProgress(tr)
    terminal_handler = ProgressLogHandler(progress)
    terminal_handler.setFormatter(logging.Formatter("[%(asctime)s] %(levelname)s %(message)s", datefmt="%H:%M:%S"))
    logger.addHandler(terminal_handler)
    logger.info("Version %s, distribution %s", VERSION, read_os_release())
    logger.info(tr("log_location", path=log_path))
    base = Path(os.environ.get("STARTER_KIT_BASE", Path(__file__).parent)).resolve()
    try:
        with tempfile.TemporaryDirectory(prefix="handheld-starter-kit-") as directory:
            wizard = Wizard(ui, home, base, Path(directory), logger, log_path, dry=args.dry_run, recommend=args.recommend, progress=progress)
            wizard.run()
    except Cancelled:
        logger.info("Cancelled by user")
    except (Exception, KeyboardInterrupt) as exc:
        logger.exception("Installer stopped")
        ui.info("Linux Handheld Starter Kit", tr("failed", item="Linux Handheld Starter Kit", error=clean(exc, 1600)) + "\n" + str(log_path), error=True)
        return 1
    finally:
        progress.finish()
        logger.removeHandler(terminal_handler)
        terminal_handler.close()
        lock.close()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)

HANDHELD_STARTER_KIT_PYTHON
python3 "$starter_kit_work/starterkit.py" "$@" &
starter_kit_child=$!
set +e
wait "$starter_kit_child"
starter_kit_status=$?
set -e
exit "$starter_kit_status"

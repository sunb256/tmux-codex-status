
  - tmux

    - tmux/codex-status.tmux
      tmux側の本体設定。ステータス表示の書式と prefix+w の再バインドを定義。


 - scripts

    - scripts/lib/codex-state.sh
      共通ライブラリ。notifyイベント→R/W/I/E変換、状態正規化、優先度判定を提供。

    - scripts/codex-notify.sh
      Codexの notify フック受け口。現在ペインの状態を TMUX_CODEX_PANE_*_STATE に保存。

    - scripts/codex-window-badge.sh
      ウィンドウ単位のバッジ（背景色付き）を計算・出力。複数ペイン状態を集約して表示。

    - scripts/codex-refresh-pane-badges.sh
      全ペインの @codex-status-pane-badge（プレーン文字列）を更新。prefix+w メニュー用。

    - scripts/codex-pane-menu.sh
      display-menu 形式のペイン一覧を生成して表示。各行に必要なら 🤖 R/W/I/E を付与。

    - scripts/codex-select-pane.sh
      メニュー選択時に対象 session:window.pane へ移動する処理。

    - scripts/codex-state-gc.sh
      既に消えたペインの TMUX_CODEX_PANE_* 環境変数を掃除。


  - test

    - tests/run-all.sh
      全テスト実行のエントリーポイント。

    - tests/test-state-map.sh
      イベント→状態変換ロジックのテスト。

    - tests/test-state-rank.sh
      状態の正規化と優先度（E > I > R > W）テスト。

    - tests/test-window-badge.sh
      ウィンドウバッジ集約・表示ロジックの統合テスト。

    - tests/test-pane-badge.sh
      ペインバッジ更新ロジックの統合テスト。

    - tests/test-pane-menu.sh
      prefix+w 用メニューコマンド生成内容のテスト。

    - tests/test-gc.sh
      stale状態のGC（不要環境変数削除）テスト。
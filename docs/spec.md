
  - tmux

    - tmux/codex-status.tmux
      tmux側の本体設定。ステータス表示の書式と prefix+w の再バインドを定義。


 - src

    - src/tmux_codex_status/cli.py
      CLIエントリーポイント。tmux呼び出しや notify を受けて処理を振り分け。

    - src/tmux_codex_status/commands.py
      tmuxとの連携ロジック本体。バッジ計算・メニュー生成・GCなどを実装。

    - src/tmux_codex_status/session_scan.py
      Codexセッションログからの状態推定。

    - src/tmux_codex_status/state.py
      notifyイベント→R/W/I/E変換、状態正規化、優先度判定。


  - test

    - pytests/test_state.py
      イベント→状態変換ロジックのテスト。

    - pytests/test_session_scan.py
      セッションログからの状態推定テスト。

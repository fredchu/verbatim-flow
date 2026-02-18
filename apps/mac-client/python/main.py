from __future__ import annotations

from verbatim_flow.app import VerbatimFlowApp
from verbatim_flow.config import parse_args, to_config
from verbatim_flow.recorder import list_audio_devices


def main() -> None:
    args = parse_args()
    if args.list_devices:
        print(list_audio_devices())
        return

    config = to_config(args)
    app = VerbatimFlowApp(config)
    app.run()


if __name__ == "__main__":
    main()

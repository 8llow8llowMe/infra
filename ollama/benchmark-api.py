#!/usr/bin/env python3
"""Measure repeatable Ollama API latency without printing model output."""

import argparse
import json
import time
import urllib.error
import urllib.request


def seconds(value):
    return (value or 0) / 1_000_000_000


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:11434")
    parser.add_argument("--model", default="gpt-oss:20b")
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--think", choices=("default", "low", "medium", "high"), default="default")
    parser.add_argument("--num-ctx", type=int, default=4096)
    parser.add_argument("--num-predict", type=int, default=96)
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    if args.runs < 1 or args.num_ctx < 1 or args.num_predict < 1:
        parser.error("runs, num-ctx, and num-predict must be positive")

    payload = {
        "model": args.model,
        "messages": [{"role": "user", "content": "한국어로 서버 상태를 점검하는 방법을 세 문장으로 설명해줘."}],
        "stream": False,
        "options": {"num_ctx": args.num_ctx, "num_predict": args.num_predict},
    }
    if args.think != "default":
        payload["think"] = args.think
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    endpoint = args.url.rstrip("/") + "/api/chat"
    print("run wall_s load_s prompt_s decode_s output_tokens tok_per_s")

    for run in range(1, args.runs + 1):
        request = urllib.request.Request(endpoint, data=data, headers={"Content-Type": "application/json"})
        start = time.perf_counter_ns()
        try:
            with urllib.request.urlopen(request, timeout=args.timeout) as response:
                result = json.load(response)
        except urllib.error.HTTPError as exc:
            raise SystemExit(f"HTTP {exc.code}: {exc.read().decode('utf-8', 'replace')}") from exc
        wall = (time.perf_counter_ns() - start) / 1_000_000_000
        decode = seconds(result.get("eval_duration"))
        tokens = result.get("eval_count", 0)
        rate = tokens / decode if decode else 0
        print(
            f"{run:>3} {wall:>6.2f} {seconds(result.get('load_duration')):>6.2f} "
            f"{seconds(result.get('prompt_eval_duration')):>8.2f} {decode:>8.2f} "
            f"{tokens:>13} {rate:>9.2f}"
        )


if __name__ == "__main__":
    main()

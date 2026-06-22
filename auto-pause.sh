#!/bin/bash

LOG_FILE="/tmp/autopause.log"
LOCK_FILE="/tmp/autopause_run.lock"
export LC_ALL=C

# 每次服务启动时清理锁
rm -f "$LOCK_FILE"

# 核心动作：静音并尝试暂停
mute_and_pause() {
    # 1. 釜底抽薪：无论如何，先把系统当前默认输出设备的音量拉到 0%
    pactl set-sink-volume @DEFAULT_SINK@ 0% >> "$LOG_FILE" 2>&1

    # 2. 尽人事：依然尝试去暂停网易云（保留进度，省点电）
    for player in $(playerctl -l 2>/dev/null); do
        if playerctl -p "$player" status 2>/dev/null | grep -q "Playing"; then
            echo "[$(date)] Sending PAUSE specifically to: $player" >> "$LOG_FILE"
            playerctl -p "$player" pause >> "$LOG_FILE" 2>&1
        fi
    done
}

# 带有“并发锁”的智能监控
smart_suppress() {
    # 防并发锁
    if [ -f "$LOCK_FILE" ]; then
        return
    fi

    touch "$LOCK_FILE"
    echo "[$(date)] Starting mute & pause loop (8s)..." >> "$LOG_FILE"

    # 循环 8 秒。把 mute_and_pause 放进循环的好处是：
    # 即使系统切换扬声器花了几秒钟，一旦切换完成，扬声器的音量也会立刻被脚本瞬间拉到 0
    for i in {1..8}; do
        mute_and_pause
        sleep 1
    done

    echo "[$(date)] Monitoring finished." >> "$LOG_FILE"
    rm -f "$LOCK_FILE"
}

echo "[$(date)] Service started (Volume Mute + Strike Mode)." >> "$LOG_FILE"

pactl subscribe | while read -r line; do
    if echo "$line" | grep -qE "Event 'remove' on (sink|card)"; then

        # 严格过滤软件层面的变动
        if echo "$line" | grep -q "sink-input"; then
            continue
        fi

        echo "[$(date)] Physical Remove: $line" >> "$LOG_FILE"
        echo "[$(date)] FORCE SETTING VOLUME TO 0%" >> "$LOG_FILE"

        # 立即静音并暂停
        mute_and_pause

        # 启动后台循环，确保切换后的扬声器也被静音
        smart_suppress &

    fi
done

#!/usr/bin/env python3
"""
Douyu (斗鱼) WebSocket chat sending protocol probe.

This script analyzes and tests the Douyu web chat sending mechanism:
1. Connects to the danmaku WebSocket server
2. Performs authentication (loginreq)
3. Attempts to send a chat message (chatmessage)

Protocol reference:
- Douyu uses a custom STT (Serialized Tag Text) protocol over WebSocket
- Messages are encoded as: type@=key/value@=value/...
- Binary framing: [4-byte total_len][4-byte total_len][2-byte type=689][1-byte encrypted=0][1-byte reserved=0][body...][0x00]

Usage:
  python douyu_chat_send_probe.py --room <room_id> --cookie "<douyu_cookie>"
"""

import asyncio
import hashlib
import json
import struct
import time
import uuid
import argparse

try:
    import websockets
except ImportError:
    print("Installing websockets...")
    import subprocess
    subprocess.check_call(["pip", "install", "websockets"])
    import websockets


# ── Douyu STT serialization ──────────────────────────────────────────

def escape_stt(s: str) -> str:
    """Escape special characters for STT format."""
    return s.replace("/", "@S").replace(":", "@A").replace("@", "@A")


def serialize_stt(body: str) -> bytes:
    """
    Serialize a STT string into Douyu binary frame.
    Frame layout:
      [4 LE bytes] payload_len  (header2 + body + 1 trailing null)
      [4 LE bytes] payload_len  (duplicate)
      [2 LE bytes] 689          (client→server magic)
      [1 byte]    0             (encrypted flag)
      [1 byte]    0             (reserved)
      [N bytes]   UTF-8 body
      [1 byte]    0x00          (trailing null)
    """
    body_bytes = body.encode("utf-8")
    payload_len = 4 + 4 + len(body_bytes) + 1  # header2 + body + null
    header = struct.pack("<II", payload_len, payload_len)
    magic = struct.pack("<HBB", 689, 0, 0)
    return header + magic + body_bytes + b"\x00"


def deserialize_stt_body(data: bytes, offset: int = 12) -> str:
    """Extract the STT body string from a binary frame starting at offset."""
    # Find trailing null
    end = data.find(b"\x00", offset)
    if end == -1:
        end = len(data)
    return data[offset:end].decode("utf-8", errors="replace")


def parse_stt(s: str) -> dict:
    """Parse a STT string into a nested dict."""
    if "@" not in s:
        return s
    result = {}
    parts = s.split("/")
    for part in parts:
        if not part or "@=" not in part:
            continue
        key, val = part.split("@=", 1)
        # Unescape
        val = val.replace("@S", "/").replace("@A", "@")
        # Recurse if nested STT
        if "@=" in val:
            result[key] = parse_stt(val)
        else:
            result[key] = val
    return result


# ── Cookie parsing ───────────────────────────────────────────────────

def parse_cookie(cookie_str: str) -> dict:
    """Parse cookie string into a dict."""
    cookies = {}
    for item in cookie_str.split(";"):
        item = item.strip()
        if "=" in item:
            key, val = item.split("=", 1)
            cookies[key.strip()] = val.strip()
    return cookies


# ── VK (verification key) generation ────────────────────────────────

def generate_vk(roomid: str, devid: str, rt: str) -> str:
    """
    Generate verification key for login request.
    VK = md5(roomid + devid + rt + "123456789012345678901234567890")
    """
    raw = f"{roomid}{devid}{rt}123456789012345678901234567890"
    return hashlib.md5(raw.encode("utf-8")).hexdigest()


# ── Main protocol probe ─────────────────────────────────────────────

async def probe_douyu_chat(room_id: str, cookie_str: str, test_message: str):
    """
    Connect to Douyu danmaku WebSocket and probe chat sending.
    """
    print(f"\n{'='*60}")
    print(f"Douyu Chat Sending Protocol Probe")
    print(f"{'='*60}")
    print(f"Room ID: {room_id}")
    print(f"Cookie length: {len(cookie_str)}")
    print(f"Test message: {test_message}")

    # Parse cookies
    cookies = parse_cookie(cookie_str)
    uid = cookies.get("acf_uid", "")
    stk = cookies.get("acf_stk", "")
    aa1 = cookies.get("acf_aa1", "")
    print(f"\nCookie analysis:")
    print(f"  acf_uid: {uid}")
    print(f"  acf_stk: {'<present>' if stk else '<missing>'}")
    print(f"  acf_aa1: {'<present>' if aa1 else '<missing>'}")

    if not uid:
        print("\n[ERROR] acf_uid not found in cookie. User may not be logged in.")
        return False

    # Generate device ID
    devid = str(uuid.uuid4())
    rt = str(int(time.time()))

    # WebSocket URL
    ws_url = "wss://danmuproxy.douyu.com:8506"
    print(f"\nConnecting to: {ws_url}")

    try:
        async with websockets.connect(ws_url) as ws:
            print("[OK] WebSocket connected")

            # Step 1: Send loginreq with authentication
            vk = generate_vk(room_id, devid, rt)
            login_body = (
                f"type@=loginreq/"
                f"roomid@={room_id}/"
                f"devid@={devid}/"
                f"rt@={rt}/"
                f"ver@=21952015/"
                f"vk@={vk}/"
                f"ct@=1/"
            )
            # Add auth cookies if available
            if stk:
                login_body += f"stk@={stk}/"
            if aa1:
                login_body += f"aa1@={aa1}/"

            print(f"\nStep 1: Sending loginreq...")
            print(f"  loginreq body (first 200 chars): {login_body[:200]}")
            login_packet = serialize_stt(login_body)
            print(f"  Packet size: {len(login_packet)} bytes")
            await ws.send(login_packet)

            # Wait for login response
            print(f"\nStep 2: Waiting for login response...")
            response = await asyncio.wait_for(ws.recv(), timeout=10)
            if isinstance(response, bytes):
                # Parse binary response
                # Extract all packets from the frame
                offset = 0
                while offset < len(response):
                    if offset + 4 > len(response):
                        break
                    msg_len = struct.unpack("<I", response[offset:offset+4])[0]
                    frame_len = msg_len + 4
                    if offset + frame_len > len(response):
                        break
                    body = deserialize_stt_body(response, offset + 12)
                    if body:
                        parsed = parse_stt(body)
                        print(f"  Response packet: {json.dumps(parsed, ensure_ascii=False, indent=2)[:500]}")
                    offset += frame_len
            else:
                print(f"  Response (text): {response}")

            # Step 3: Send joingroup
            print(f"\nStep 3: Sending joingroup...")
            join_body = f"type@=joingroup/rid@={room_id}/gid@=-9999/"
            await ws.send(serialize_stt(join_body))

            # Wait a bit for group join response
            try:
                response = await asyncio.wait_for(ws.recv(), timeout=5)
                if isinstance(response, bytes):
                    offset = 0
                    while offset < len(response):
                        if offset + 4 > len(response):
                            break
                        msg_len = struct.unpack("<I", response[offset:offset+4])[0]
                        frame_len = msg_len + 4
                        if offset + frame_len > len(response):
                            break
                        body = deserialize_stt_body(response, offset + 12)
                        if body:
                            parsed = parse_stt(body)
                            print(f"  Join response: {json.dumps(parsed, ensure_ascii=False, indent=2)[:500]}")
                        offset += frame_len
            except asyncio.TimeoutError:
                print("  No join response (timeout - may be normal)")

            # Step 4: Attempt to send chat message
            print(f"\nStep 4: Attempting to send chat message...")
            ct = str(int(time.time() * 1000))
            chat_body = (
                f"type@=chatmessage/"
                f"roomid@={room_id}/"
                f"content@={escape_stt(test_message)}/"
                f"col@=0/"
                f"pt@=0/"
                f"ct@={ct}/"
                f"sn@=0/"
                f"ss@=0/"
                f"uid@={uid}/"
            )
            print(f"  Chat body (first 200 chars): {chat_body[:200]}")
            chat_packet = serialize_stt(chat_body)
            print(f"  Packet size: {len(chat_packet)} bytes")

            await ws.send(chat_packet)
            print(f"  Chat packet sent successfully!")

            # Step 5: Wait for response / echo
            print(f"\nStep 5: Waiting for server response...")
            try:
                for i in range(5):  # Wait up to 5 messages
                    response = await asyncio.wait_for(ws.recv(), timeout=5)
                    if isinstance(response, bytes):
                        offset = 0
                        while offset < len(response):
                            if offset + 4 > len(response):
                                break
                            msg_len = struct.unpack("<I", response[offset:offset+4])[0]
                            frame_len = msg_len + 4
                            if offset + frame_len > len(response):
                                break
                            body = deserialize_stt_body(response, offset + 12)
                            if body:
                                parsed = parse_stt(body)
                                ptype = parsed.get("type", "unknown") if isinstance(parsed, dict) else "raw"
                                print(f"  [{i+1}] type={ptype}: {json.dumps(parsed, ensure_ascii=False)[:300]}")
                                # If we see our message echoed back, success!
                                if isinstance(parsed, dict) and parsed.get("type") == "chatmsg":
                                    txt = parsed.get("txt", "")
                                    if txt == test_message:
                                        print(f"\n  ✓ Chat message echoed back by server - SUCCESS!")
                                        return True
                                elif isinstance(parsed, dict) and parsed.get("type") == "error":
                                    print(f"\n  ✗ Server returned error: {parsed}")
                                    return False
                            offset += frame_len
            except asyncio.TimeoutError:
                print("  No more messages (timeout)")

            print(f"\n[INFO] Probe completed. Check if message appeared in the live room.")
            return True

    except Exception as e:
        print(f"\n[ERROR] {e}")
        import traceback
        traceback.print_exc()
        return False


async def main():
    parser = argparse.ArgumentParser(description="Douyu chat sending protocol probe")
    parser.add_argument("--room", required=True, help="Room ID")
    parser.add_argument("--cookie", required=True, help="Douyu cookie string (from browser)")
    parser.add_argument("--message", default="测试弹幕 PureLive", help="Test message to send")
    args = parser.parse_args()

    await probe_douyu_chat(args.room, args.cookie, args.message)


if __name__ == "__main__":
    asyncio.run(main())

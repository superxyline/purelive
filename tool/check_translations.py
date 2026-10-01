# -*- coding: utf-8 -*-
"""校验 assets/translations/*.json 语法完整性。

JSON 写坏会导致 App 启动即崩（unexpected character），构建前务必校验：
    python tool/check_translations.py
"""
import glob
import json
import os
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bad = 0
for f in sorted(glob.glob(os.path.join(root, 'assets', 'translations', '*.json'))):
    try:
        json.load(open(f, encoding='utf-8'))
        print('OK  ', os.path.basename(f))
    except Exception as e:
        bad += 1
        print('BROKEN', os.path.basename(f), '->', e)

sys.exit(1 if bad else 0)

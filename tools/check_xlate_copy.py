#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Check that tests/xlate_test.c tests the same function that patch 0001 adds.

Usage: check_xlate_copy.py PATCH TEST_C
Extracts anbernic_rg34xxsp_efuse_xlate() from the patch's added lines and from the test file
and compares them (whitespace-insensitive). Exit 1 if they differ. Python stdlib only.
"""
import re
import sys

NAME = 'anbernic_rg34xxsp_efuse_xlate'


def extract(lines):
    out, depth, inside = [], 0, False
    for line in lines:
        if not inside and re.match(r'static u32 ' + NAME + r'\(', line):
            inside = True
        if inside:
            out.append(line)
            depth += line.count('{') - line.count('}')
            if depth == 0 and '}' in line:
                break
    return [re.sub(r'\s+', ' ', l).strip() for l in out if l.strip()]


patch = [l[1:] for l in open(sys.argv[1]) if l.startswith('+') and not l.startswith('+++')]
test = open(sys.argv[2]).read().splitlines()
a, b = extract(patch), extract(test)
if not a or not b:
    sys.exit(f'{NAME} not found in ' + (sys.argv[1] if not a else sys.argv[2]))
if a != b:
    for x, y in zip(a, b):
        if x != y:
            print(f'patch: {x}\ntest:  {y}')
            break
    sys.exit('the test copy differs from the function in the patch')
print(f'  {NAME}: test copy identical to the patch ({len(a)} lines)')

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json
import re
import sys
from base64 import b64decode
from urllib.parse import unquote, urlparse
from urllib.request import urlopen

gfwlist_url = 'https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt'
tlds_url = 'https://github.com/fanck0605/tld_spider/raw/main/tlds.json'

extra_sld_parts = {'a', 'go', 'or', 'pp'}


def obtain_domain(url: str):
    hostname = urlparse(url).hostname
    # convert to punycode
    return hostname.encode('idna').decode('utf-8')


def obtain_second_level_domain(domain: str, tlds: dict[str, set[str]]):
    all_tlds = tlds['all']
    cc_tlds = tlds['country-code']

    part_list = domain.split('.')
    list_size = len(part_list)

    if list_size > 2:
        # example.jp.net
        if part_list[-1] in all_tlds and part_list[-2] in cc_tlds:
            return '.'.join(part_list[-3:])
        # example.com.hk, example.go.jp
        if part_list[-1] in cc_tlds and (part_list[-2] in all_tlds or part_list[-2] in extra_sld_parts):
            return '.'.join(part_list[-3:])

    if list_size > 1:
        # example.com
        if part_list[-1] in all_tlds:
            return '.'.join(part_list[-2:])

    return None


def parse_tlds(content: str):
    raw_tlds = json.loads(content)

    return {
        'all': set[str](map(lambda i: i['tld'], raw_tlds)),
        'country-code': set[str](map(lambda i: i['tld'], filter(lambda i: i['type'] == 'country-code', raw_tlds)))
    }


def expend_grouped_or(regex: str):
    m = re.match(r'(.*)(?<!\\)\((.*?)(?<!\\)\)(?![*+?{])(.*)', regex)

    if not m:
        yield regex
        return

    prefix = m.group(1)
    items = m.group(2).split('|')
    suffix = m.group(3)
    for i in items:
        yield from expend_grouped_or(prefix + i + suffix)


def expend_rules(line: str):
    if not line.startswith('/'):
        yield line
        return

    raw_line = line
    line = line[1:-1]
    line = line.lstrip('^')
    line = line.rstrip('$')
    line = line.replace(r'\/', '/')

    for rule in expend_grouped_or(line):
        if r'\..*' in rule:
            print('Ignore regex rule: ', rule)
            continue

        rule = re.sub(r'(?<!\\)\(.*(?<!\\)\)[*+?]', '', rule)
        rule = re.sub(r'(?<!\\)\(.*(?<!\\)\){.*?}', '', rule)
        rule = re.sub(r'(?<!\\)\[.*(?<!\\)][*+?]', '', rule)
        rule = re.sub(r'(?<!\\)\[.*(?<!\\)]{.*?}', '', rule)
        rule = re.sub(r'(?<!\\)\\.[*+?]', '', rule)
        rule = re.sub(r'(?<!\\)\\.{.*?}', '', rule)
        rule = re.sub(r'.[*+?]', '', rule)
        rule = re.sub(r'.{.*?}', '', rule)
        rule = rule.replace(r'\.', '.')

        if raw_line != rule:
            print('Warning: ', raw_line, ' -> ', rule)

        yield rule


def parse_gfwlist(content: str, tlds: dict[str, set[str]]):
    domains = set[str]()
    for line in content.splitlines(keepends=False):
        if not line:
            # ignore null or ''
            continue
        if line.startswith('!'):
            # ignore comment
            continue
        if line.startswith('['):
            # ignore [AutoProxy x.x.x]
            continue
        if line.startswith('@'):
            # ignore white list
            continue

        for rule in expend_rules(line):
            rule = unquote(rule, 'utf-8')

            if '.' not in rule:
                print('Ignore keywords rule: ', rule)
                continue

            if rule.find('.*') >= 0:
                print('Ignore glob rule: ', rule)
                continue

            rule = replace_globs(rule)

            rule = strip_prefix(rule)

            domain = obtain_domain('https://' + rule)

            sld = obtain_second_level_domain(domain, tlds)
            if not sld:
                print('Ignore invalid domain: ', domain)
                continue

            domains.add(sld)

    return domains


def replace_globs(line: str):
    raw_line = line
    line = re.sub(r'(?<=\w)\*(?=\w)', '/', line)
    line = line.replace('*', '')
    if raw_line != line:
        print('Warning: ', raw_line, ' -> ', line)
    return line


def strip_prefix(line: str):
    line = line.lstrip('|')
    line = re.sub(r'^\w+?://', '', line)
    line = line.lstrip('.')
    return line


def main():
    conf_file = sys.argv[1] if len(sys.argv) > 1 else None
    group_name = sys.argv[2] if len(sys.argv) > 2 else None

    print('Downloading tlds from %s' % tlds_url)
    with urlopen(tlds_url) as tlds_response:
        tlds_body = tlds_response.read().decode('utf-8')
        tlds = parse_tlds(tlds_body)

        print('Downloading gfwlist from %s' % gfwlist_url)
        with urlopen(gfwlist_url) as gfwlist_response:
            gfwlist_body = gfwlist_response.read()
            decoded_gfwlist = b64decode(gfwlist_body).decode('utf-8')
            gfwlist = parse_gfwlist(decoded_gfwlist, tlds)

            with open(conf_file or 'gfwlist.conf', 'w') as f:
                for i in sorted(gfwlist):
                    f.write("nameserver /%s/%s\n" % (i, group_name or 'foreign'))


if __name__ == '__main__':
    main()

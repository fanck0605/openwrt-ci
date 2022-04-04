#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import re
import sys
from base64 import b64decode
from urllib.parse import unquote, urlparse
from urllib.request import urlopen

gfwlist_url = 'https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt'
suffixes_url = 'https://publicsuffix.org/list/public_suffix_list.dat'
tlds_url = 'https://data.iana.org/TLD/tlds-alpha-by-domain.txt'


def obtain_domain(url: str):
    hostname = urlparse(url).hostname
    # convert to punycode
    return hostname.encode('idna').decode('utf-8')


def obtain_second_level_domain(domain: str, tlds: set[str]):
    part_list = domain.split('.')
    list_size = len(part_list)
    sld = domain
    for i in range(1, list_size):
        # suffix of sld
        suffix = '.'.join(part_list[i:])
        if suffix in tlds:
            return sld
        sld = suffix
    return None


def parse_tlds(content: str):
    tlds = set[str]()
    for line in content.splitlines(keepends=False):
        if line.startswith('#'):
            continue
        if not line:
            continue
        tlds.add(line.lower())
    return tlds


def parse_suffixes(content: str, tlds: set[str]):
    oooo = {'a', 'go', 'or', 'pp'}
    tld_pluses = set[str](tlds)
    for line in content.splitlines(keepends=False):
        if not line:
            # ignore null or ''
            continue
        if line.startswith('//'):
            # ignore comment
            continue
        suffix = line.encode('idna').decode('utf-8')
        part_list = suffix.split('.')
        list_size = len(part_list)
        if list_size < 2:
            continue
        part_list = part_list[-2:]
        if (part_list[0] in tlds or part_list[0] in oooo) and part_list[1] in tlds:
            tld_pluses.add('.'.join(part_list))
    return tld_pluses


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


def parse_gfwlist(content: str, tlds: set[str]):
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

        print('Downloading suffixes from %s' % suffixes_url)
        with urlopen(suffixes_url) as suffixes_response:
            suffixes_body = suffixes_response.read().decode('utf-8')
            tld_pluses = parse_suffixes(suffixes_body, tlds)

            print('Downloading gfwlist from %s' % gfwlist_url)
            with urlopen(gfwlist_url) as gfwlist_response:
                gfwlist_body = gfwlist_response.read()
                decoded_gfwlist = b64decode(gfwlist_body).decode('utf-8')
                gfwlist = parse_gfwlist(decoded_gfwlist, tld_pluses)

                with open(conf_file or 'gfwlist.conf', 'w') as f:
                    for i in sorted(gfwlist):
                        f.write("nameserver /%s/%s\n" % (i, group_name or 'foreign'))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import re
import sys
from base64 import b64decode
from urllib.parse import unquote, urlparse
from urllib.request import urlopen

gfwlist_url = 'https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt'
tlds_url = 'https://publicsuffix.org/list/public_suffix_list.dat'


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
        if not line:
            # ignore null or ''
            continue
        if line.startswith('//'):
            # ignore comment
            continue
        tld = line.encode('idna').decode('utf-8')
        tlds.add(tld)
    return tlds


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

        if line.startswith('/'):
            if line.find('*') >= 0 \
                    or line.find('[') >= 0 \
                    or line.find('|') >= 0 \
                    or line.find('(') >= 0:
                print('Ignore regex rule: ', line)
                continue

            # support limit regex
            line = replace_regex(line)

        line = unquote(line, 'utf-8')

        if '.' not in line:
            print('Ignore keywords rule: ', line)
            continue

        if line.find('.*') >= 0:
            print('Ignore glob rule: ', line)
            continue

        line = replace_globs(line)

        line = strip_prefix(line)

        domain = obtain_domain('https://' + line)

        sld = obtain_second_level_domain(domain, tlds)
        if not sld:
            print('Ignore invalid domain: ', domain)
            continue

        domains.add(sld)

    return domains


def replace_regex(line: str):
    raw_line = line
    line = re.findall('(?<=/).*(?=/)', line)[0]
    line = line.replace(r'\/', '/')
    line = line.replace(r'\.', '.')
    line = re.sub(r'.\?', '', line)
    if raw_line != line:
        print('Warning: ', raw_line, ' -> ', line)
    return line


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

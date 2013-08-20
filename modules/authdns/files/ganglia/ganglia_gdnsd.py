#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Copyright (c) 2013 Faidon Liambotis
# Copyright (c) 2013 Wikimedia Foundation, Inc.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
"""Gmond module for gdnsd statistics

:copyright: (c) 2013 Faidon Liambotis and Wikimedia Foundation Inc.
:author: Faidon Liambotis
:license: GPLv2+
"""

import urllib2
import json


CONF = {
    'stats_url': 'http://127.0.0.1:3506/json',
    'prefix': 'gdnsd',
    'groups': 'gdnsd',
}
DESCRIPTIONS = {
    'stats_v6': 'DNS queries over IPv6',
    'stats_badvers': 'DNS BADVERS responses',
    'stats_formerr': 'DNS FORMERR responses',
    'stats_noerror': 'DNS NOERROR responses',
    'stats_notimp': 'DNS NOTIMP responses',
    'stats_nxdomain': 'DNS NXDOMAIN responses',
    'stats_refused': 'DNS REFUSED responses',
    'stats_dropped': 'DNS dropped packets',
    'stats_edns': 'DNS EDNS queries',
    'stats_edns_clientsub': 'DNS queries with EDNS Client Subnet',
    'udp_reqs': 'DNS UDP requests',
    'tcp_reqs': 'DNS TCP requests',
    'udp_edns_big': 'DNS UDP EDNS big',
    'udp_tc': 'DNS UDP TC-bit',
    'udp_edns_tc': 'DNS UDP EDNS TC-bit',
    'udp_sendfail': 'DNS UDP sendfail',
    'udp_recvfail': 'DNS UDP recvfail',
    'tcp_sendfail': 'DNS TCP sendfail',
    'tcp_recvfail': 'DNS TCP recvfail',
}


def build_desc(skel, prop):
    """Build a description dict from a template.

    :param skel: template dict
    :param prop: substitution dict
    :returns: New dict
    """
    new = skel.copy()
    for key, value in prop.iteritems():
        new[key] = value
    return new


def fetch_metrics(url=CONF['stats_url']):
    """Fetches & decodes metrics from gdnsd.

    :param url: URL for gdnsd's json output
    :returns: decoded dict
    """
    metrics = {}
    try:
        response = urllib2.urlopen(url)
        data = response.read()
        response.close()
        metrics = json.loads(data)
    except (urllib2.URLError, KeyError):
        pass

    return metrics


def metric_handler(name):
    """Callback to return the current value for a metric.

    :param name: metric name
    :returns: metric value
    """
    raw = fetch_metrics()
    try:
        _, category, metric = name.split('_', 2)
        val = raw[category][metric]
    except KeyError:
        val = 0
    return val


def metric_init(params):
    """Initialize module at gmond startup."""

    for key, value in params.iteritems():
        CONF[key] = value

    skel = {
        #'name': '',
        #'description': '',
        'call_back': metric_handler,
        'time_max': 60,
        'value_type': 'uint',
        'units': 'pkts/s',
        'slope': 'positive',
        'format': '%u',
        'groups': CONF['groups'],
    }

    raw = fetch_metrics()
    descriptors = []
    for category in raw:
        try:
            for metric in raw[category]:
                name = str("%s_%s_%s" % (CONF['prefix'], category, metric))
                desc = str("%s_%s" % (category, metric))
                descriptors.append(build_desc(skel, {
                    'name': name,
                    'description': DESCRIPTIONS.get(desc, desc),
                }))
        except TypeError:
            # root-level values, currently just uptime, ignore
            continue

    return descriptors


def metric_config(params):
    """Returns a pyconf to accompany this"""
    import textwrap

    descriptors = metric_init(params)

    out = """\
    # gdnsd plugin for Ganglia monitor, automatically generated config file

    modules {
        module {
            name = "gdnsd"
            language = "python"
        }
    }

    collection_group {
        collect_every = 15
        time_threshold = 15
    """

    for desc in descriptors:
        out += """
        metric {
            name = "%(name)s"
            title = "%(description)s"
        }""" % desc

    out += """
    }"""

    return textwrap.dedent(out)


def metric_cleanup():
    """Clean up on gmond shutdown. No-op."""
    pass


if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == 'config':
        print metric_config({})
    else:
        for d in metric_init({}):
            d['value'] = d['call_back'](d['name'])
            print ' %(name)s: %(units)s %(value)s [%(description)s]' % d

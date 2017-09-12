#!/usr/bin/env python2
# -*- coding: utf-8 -*-
"""
Cyclogram checking tool. Ver 0.5

Created on Thu Jan 26 15:25:53 2017

@author: A. Kutkin
"""
import matplotlib as mpl
mpl.use('agg')
import os
import sys
import re
import datetime
import logging
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
import matplotlib.dates as mdates
#import matplotlib as mpl
mpl.rcParams['pdf.fonttype'] = 3

# test
#cfile = '/home/osh/Downloads/ra10062017100825-11062017085940.01.035'
#cfile = '/home/osh/tmp/ra09092017195825-10092017230505.01.035'
#cfile = '/home/osh/Downloads/ra09092017195825-10092017230505.01.035'
#cfile = '/home/osh/Downloads/ra11092017121325-13092017085230.01.035'
#sys.argv.append(cfile)


if len(sys.argv) < 2:
    print("Error: Specify file name")
    sys.exit(1)
else:
    cfile = sys.argv[1]


if not os.path.isfile(cfile):
    print("Error: No such file: {}".format(cfile))
    sys.exit(1)

figpath, _ = os.path.split(cfile)
logfile = os.path.join(figpath, 'cyc.log')

# For windows corect path representation
try:
    from ctypes import create_unicode_buffer, windll
    figfile_base = u"{}".format(os.path.abspath(cfile.decode('windows-1251')))
    BUFFER_SIZE = 500
    buffer = create_unicode_buffer(BUFFER_SIZE)
    get_long_path_name = windll.kernel32.GetLongPathNameW
    get_long_path_name(unicode(figfile_base), buffer, BUFFER_SIZE)
    figfile_base = buffer.value
except:
    figfile_base = cfile


reload(logging) # reload the module to avoid multiple Spyder console output
logger = logging.getLogger(__name__)
logger.setLevel('DEBUG')
hndlr1 = logging.StreamHandler()
hndlr2 = logging.FileHandler(logfile, mode='w')
frmtr = logging.Formatter(fmt='%(levelname)s: %(message)s '
    '(%(asctime)s; %(filename)s:%(lineno)d)',
    datefmt="%Y-%m-%d %H:%M:%S")
hndlr1.setFormatter(frmtr)
hndlr2.setFormatter(frmtr)
logger.addHandler(hndlr1)
logger.addHandler(hndlr2)


dtfmt = '%d.%m.%Y %H:%M:%S'
timeptrn = '[0-3]\d\.[0-1]\d\.\d{4}\s[0-2]\d:[0-5]\d:[0-5]\d'


def parsum(lst1, lst2):
    """ sum of two lists """
    return [a + b for a, b in zip(lst1, lst2)]


with open(cfile, 'r') as cf:
    fulltext = cf.read()
    sessions = re.split('[Ss]tart\s{0,1}=', fulltext)
    chapters = re.split('//\s*[Cc]hapter\s*\d{1,2}', fulltext)
    lines = fulltext.split('\n')
    logger.info('Processing file {} ({} lines)'.format(cfile, len(lines)))
    if len(sessions) > 1:
        logger.info('{} sessions detected'.format(len(sessions) -1))
    else:
        logger.debug('No sessions found')
    if len(chapters) != len(sessions):
        logger.debug('N_chapters ({}) != N_sessions ({})'.format(len(chapters),
                                                                 len(sessions)))

cmdlines = []
for line in lines:
    if line and line.strip() and not line.startswith('//'):
        cmdlines.append(line)
try:
    cmdtimes = [datetime.datetime.strptime(_[:19], dtfmt) for _ in cmdlines]
except:
    logger.error('Bad line format: {}'.format(_))
    sys.exit(1)

tstart_global = datetime.datetime.strptime(cmdlines[0][:19], dtfmt)
tstop_global = datetime.datetime.strptime(cmdlines[-1][:19], dtfmt)

n = len(cmdtimes) # to add initial index before start

par_key135_1 = [0] * n
par_key135_2 = [0] * n

par_key6_1 = [0] * n
par_key6_2 = [0] * n

par_pow18_1 = [0] * n # ch1
par_pow18_2 = [0] * n # ch2
par_adc18_1 = [0] * n # ch1
par_adc18_2 = [0] * n # ch2
par_ng18_1 =  [0] * n # GSH-18-1 nizk, vysok
par_ng18_2 =  [0] * n # GSH-18-2 nizk, vysok
par_key18_1 = [0] * n # Key 18-1
par_key18_2 = [0] * n

par_pow92_1 = [0] * n # ch1
par_pow92_2 = [0] * n # ch2
par_adc92_1 = [0] * n # ch1
par_adc92_2 = [0] * n # ch2
par_ng92_1 =  [0] * n # GSH-18-1 nizk, vysok
par_ng92_2 =  [0] * n # GSH-18-2 nizk, vysok
par_key92_1 = [0] * n # Key 18-1
par_key92_2 = [0] * n

par_pow6_1 = [0] * n
par_pow6_2 = [0] * n
par_adc6_1 = [0] * n # ch1
par_adc6_2 = [0] * n # ch2
par_ng6_1 =  [0] * n # GSH-6-1 nizk, vysok
par_ng6_2 =  [0] * n # GSH-6-2 nizk, vysok
par_key6_1 = [0] * n # Key 6-1
par_key6_2 = [0] * n

pars = {'TS':[0]*n, 'MOD-40W':[0]*n, 'ZU':[0]*n, 'BIK':[1]*n,
        'HET-254':[0]*n, 'HET-258':[0]*n, #'FGTCH':[0]*n,
        'VK-1.35':[0]*n, 'VK-6':[0]*n, 'VK-18':[0]*n, 'VK-92':[0]*n, # FGSVCH
        'POW-1.35':[0]*n, 'HET-1.35':[0]*n, 'TRM-1.35':[0]*n, 'KEY-1.35':[0]*n,
        'POW-6':[0]*n, 'ADC-6':[0]*n, 'TRM-6':[0]*n, 'KEY-6':[0]*n,
        'POW-18':[0]*n, 'ADC-18':[0]*n, 'KEY-18':[0]*n,
        'POW-92':[0]*n,'ADC-92':[0]*n,'KEY-92':[0]*n,
        'NG-1.35':[0]*n, 'NG-6':[0]*n, 'NG-18':[0]*n, 'NG-92':[0]*n,
        '15MHz':[1]*n, '5MHz':[1]*n, 'FGTCH_SRC':[2]*n}

colors = pars.fromkeys(pars, 'k')

### Main cycle
for ind, cline in enumerate(cmdlines):
    sub = n - ind # nuber of remaining parameter values to replace

    # check if time is sorted
    if ind < len(cmdtimes)-1 and cmdtimes[ind+1] <= cmdtimes[ind]:
        logger.error('Time is not sorted after {}'.format(cmdtimes[ind-1]))
        sys.exit(1)
    # check the common cmdline structure
    if not 'SRT  PLAZMAPZ   PLAZMA=KK' in cline:
        logger.warning('Check the command line at {}'.format(cmdtimes[ind-1]))

    cmd = cline.split()[5]
    if '866-34' in cmd:
        pars['ZU'][ind:] = [1]*sub
    elif ind < n-1 and cmd == u'808' and not cmdlines[ind+1].split()[5] == '866-34':
        pars['ZU'][ind+1:] = [0]*(sub-1)
    elif ind < n-1 and cmd == u'808' and cmdlines[ind+1].split()[5] == '866-34':
        pars['ZU'][ind:] = [0]*sub
    elif cmd == u'3151':
        pars['BIK'][ind:] = [1]*sub
    elif cmd == u'3153':
        pars['BIK'][ind:] = [0]*sub
    elif cmd == u'3111':
        pars['MOD-40W'][ind:] = [0]*sub
    elif cmd == u'3112':
        pars['MOD-40W'][ind:] = [1]*sub
    elif cmd == u'3240,00000021':
#        pars['FGTCH'][ind:] = [0]*sub
        pars['HET-254'][ind+1:] = [0]*(sub-1)
        pars['HET-258'][ind+1:] = [0]*(sub-1)
    elif cmd == u'3240,0000001E':
#        pars['FGTCH'][ind:] = [1]*sub
        pars['HET-254'][ind:] = [1]*sub
    elif cmd == u'3240,0000001F':
#        pars['FGTCH'][ind:] = [1]*sub
        pars['HET-258'][ind:] = [1]*sub
    elif cmd == u'3240,0000009E':
        pars['VK-1.35'][ind+1:] = [0]*(sub-1)
        pars['VK-6'][ind+1:] = [0]*(sub-1)
        pars['VK-18'][ind+1:] = [0]*(sub-1)
        pars['VK-92'][ind+1:] = [0]*(sub-1)
    elif cmd == u'3240,0000009D':
        pars['VK-1.35'][ind:] = [1]*sub
    elif cmd == u'3240,0000009C':
        pars['VK-6'][ind:] = [1]*sub
    elif cmd == u'3240,0000009B':
        pars['VK-18'][ind:] = [1]*sub
    elif cmd == u'3240,0000009A':
        pars['VK-92'][ind:] = [1]*sub

    elif cmd == u'3127':
        pars['POW-1.35'][ind:] = [1]*sub
    elif cmd == u'3129':
        pars['POW-1.35'][ind+1:] = [0]*(sub-1)
    elif cmd == u'3124':
        pars['TRM-1.35'][ind:] = [1]*sub
    elif cmd == u'3125':
        pars['TRM-1.35'][ind+1:] = [0]*(sub-1)
    elif cmd == u'3230,3F000000':
        pars['HET-1.35'][ind+1:] = [0]*(sub-1)
    elif cmd == u'3230,30000000':
        pars['HET-1.35'][ind:] = [1]*sub

# 6 cm
# TODO: add attenuators
    elif cmd == u'3133':
        par_pow6_1[ind:] = [1]*sub
    elif cmd == u'3134':
        par_pow6_2[ind:] = [2]*sub
    elif cmd == u'3135':
        par_pow6_1[ind+1:] = [0]*(sub-1)
        par_pow6_2[ind+1:] = [0]*(sub-1)

    elif cmd == u'3130':
        pars['TRM-6'][ind:] = [1]*sub
    elif cmd == u'3132':
        pars['TRM-6'][ind+1:] = [0]*(sub-1)
    elif cmd == u'3240,00000053':
        par_adc6_1[ind:] = [1]*sub
    elif cmd == u'3240,00000054':
        par_adc6_2[ind:] = [2]*sub
    elif cmd == u'3240,00000055':
        par_adc6_1[ind+1:] = [0]*(sub-1)
        par_adc6_2[ind+1:] = [0]*(sub-1)

    elif cmd == '3240,0000004B':
        pars['NG-6'][ind:] = [1]*sub
    elif cmd == '3240,0000004C':
        pars['NG-6'][ind:] = [0]*sub

# 18 cm
    elif cmd == u'3139':
        par_pow18_1[ind:] = [1]*sub
    elif cmd == u'3140':
        par_pow18_2[ind:] = [2]*sub
    elif cmd == u'3141':
        par_pow18_1[ind+1:] = [0]*(sub-1)
        par_pow18_2[ind+1:] = [0]*(sub-1)
    elif cmd == u'3240,0000006B':
        par_adc18_1[ind:] = [1]*sub
    elif cmd == u'3240,0000006C':
        par_adc18_2[ind:] = [2]*sub
    elif cmd == u'3240,0000006D':
        par_adc18_1[ind+1:] = [0]*(sub-1)
        par_adc18_2[ind+1:] = [0]*(sub-1)
    elif cmd == '3240,00000063':
        par_ng18_1[ind:] = [1]*sub
    elif cmd == '3240,00000064':
        par_ng18_1[ind+1:] = [0]*(sub-1)
    elif cmd == '3240,00000067':
        par_ng18_2[ind:] = [2]*sub
    elif cmd == '3240,00000068':
        par_ng18_2[ind+1:] = [0]*(sub-1)

# 92 cm
    elif cmd == u'3145':
        par_pow92_1[ind:] = [1]*sub
    elif cmd == u'3146':
        par_pow92_2[ind:] = [2]*sub
    elif cmd == u'3147':
        par_pow92_1[ind+1:] = [0]*(sub-1)
        par_pow92_2[ind+1:] = [0]*(sub-1)
    elif cmd == u'3240,00000083':
        par_adc92_1[ind:] = [1]*sub
    elif cmd == u'3240,00000084':
        par_adc92_2[ind:] = [2]*sub
    elif cmd == u'3240,00000085':
        par_adc92_1[ind+1:] = [0]*(sub-1)
        par_adc92_2[ind+1:] = [0]*(sub-1)
    elif cmd == '3240,0000007B':
        par_ng92_1[ind:] = [1]*sub
    elif cmd == '3240,0000007C':
        par_ng92_1[ind+1:] = [0]*(sub-1)
    elif cmd == '3240,0000007F':
        par_ng92_2[ind:] = [2]*sub
    elif cmd == '3240,00000080':
        par_ng92_2[ind+1:] = [0]*(sub-1)
# new features (15, 5, MHz and FGTCH SRC)
    elif cmd == '3211,05052867':
        pars['15MHz'][ind:] = [1]*sub
    elif cmd == '3211,050466A1':
        pars['15MHz'][ind+1:] = [0]*(sub-1)
    elif cmd == '3240,00000017':
        pars['5MHz'][ind:] = [1]*sub
    elif cmd == '3240,00000013':
        pars['5MHz'][ind+1:] = [0]*(sub-1)
    elif cmd == '3240,0000001A': # Work FGTCh ot BRSCh-2
        pars['FGTCH_SRC'][ind+1:] = [1]*(sub-1)
    elif cmd == '3240,0000001B': # Work FGTCh s  "VIRK-1" (BVSCH-1,2)
        pars['FGTCH_SRC'][ind+1:] = [2]*(sub-1)


# NG-1.35
    if len(cmd) > 4 and cmd.startswith('3230'):
        if cmd[-3:] in ['020', '060', '080', '180']:
            pars['NG-1.35'][ind:] = [1]*sub
        elif cmd[-3:] in ['000']:
            pars['NG-1.35'][ind+1:] = [0]*(sub-1)

# Keys
# TODO: add key-sequence check
    if 1 < ind < n - 4:
        cmd_prev = cmdlines[ind-1].split()[5]
        cmd_next1 = cmdlines[ind+1].split()[5]
        cmd_next2 = cmdlines[ind+2].split()[5]
        if cmd == u'3240,000000AE' and cmd_next1 != cmd:
            if cmd_next1 == u'3240,00000092':
                if cmd_next2 == u'3240,0000008E':
                    par_key92_1[ind:] = [1]*sub
                elif cmd_next2 == u'3240,0000008F':
                    par_key92_1[ind+1:] = [0]*(sub-1)
                elif cmd_next2 == u'3240,00000090':
                    par_key18_1[ind:] = [1]*sub
                elif cmd_next2 == u'3240,00000091':
                    par_key18_1[ind+1:] = [0]*(sub-1)
            elif cmd_next1 == u'3240,00000098':
                if cmd_next2 == u'3240,0000008E':
                    par_key92_2[ind:] = [2]*sub
                elif cmd_next2 == u'3240,0000008F':
                    par_key92_2[ind+1:] = [0]*(sub-1)
                elif cmd_next2 == u'3240,00000090':
                    par_key18_2[ind:] = [2]*sub
                elif cmd_next2 == u'3240,00000091':
                    par_key18_2[ind+1:] = [0]*(sub-1)
            elif cmd_next1 == u'3240,00000093':
                if cmd_next2 == u'3240,0000008E':
                    par_key6_1[ind:] = [1]*sub
                elif cmd_next2 == u'3240,0000008F':
                    par_key6_1[ind+1:] = [0]*(sub-1)
                elif cmd_next2 == u'3240,00000090':
                    par_key135_1[ind:] = [1]*sub
                elif cmd_next2 == u'3240,00000091':
                    par_key135_1[ind+1:] = [0]*(sub-1)
            elif cmd_next1 == u'3240,00000099':
                if cmd_next2 == u'3240,0000008E':
                    par_key6_2[ind:] = [2]*sub
                elif cmd_next2 == u'3240,0000008F':
                    par_key6_2[ind+1:] = [0]*(sub-1)
                elif cmd_next2 == u'3240,00000090':
                    par_key135_2[ind:] = [2]*sub
                elif cmd_next2 == u'3240,00000091':
                    par_key135_2[ind+1:] = [0]*(sub-1)

    if ind == n - 1 and cmd != u'808':
        logger.warning('Turn off ZU expected at the end')
        colors['ZU'] = 'r'


pars['KEY-1.35'] = parsum(par_key135_1, par_key135_2)
pars['KEY-6'] = parsum(par_key6_1, par_key6_2)
pars['POW-6'] = parsum(par_pow6_1, par_pow6_2)
pars['ADC-6'] = parsum(par_adc6_1, par_adc6_2)
pars['POW-18'] = parsum(par_pow18_1, par_pow18_2)
pars['ADC-18'] = parsum(par_adc18_1, par_adc18_2)
pars['KEY-18'] = parsum(par_key18_1, par_key18_2)
pars['NG-18'] = parsum(par_ng18_1, par_ng18_2)

pars['POW-92'] = parsum(par_pow92_1, par_pow92_2)
pars['ADC-92'] = parsum(par_adc92_1, par_adc92_2)
pars['KEY-92'] = parsum(par_key92_1, par_key92_2)
pars['NG-92'] = parsum(par_ng92_1, par_ng92_2)

#pars['FGTCH_SRC'] = parsum(pars['FGTCH_SRC'], pars['FGTCH_SRC'])

### Plotting
## hatch 	[‘/’ | ‘\’ | ‘|’ | ‘-‘ | ‘+’ | ‘x’ | ‘o’ | ‘O’ | ‘.’ | ‘*’]
htch = [None, '//', '\\\\','xx']

names = ['TS', 'MOD-40W', 'ZU', 'BIK', 'HET-254', 'HET-258', 'VK-1.35', 'VK-6',
 'VK-18', 'VK-92', 'HET-1.35', 'TRM-1.35', 'POW-1.35', 'KEY-1.35', 'TRM-6',
 'POW-6', 'ADC-6', 'KEY-6', 'POW-18', 'ADC-18', 'KEY-18', 'POW-92', 'ADC-92',
 'KEY-92', 'NG-1.35', 'NG-6', 'NG-18', 'NG-92', '15MHz', '5MHz', 'FGTCH_SRC']

old_names = ['TS', '40W', 'ZU', 'BIK', 'GET-254', 'GET-258', 'VK-1.35', 'VK-6',
 'VK-18', 'VK-92', 'GET-1.35', 'TRST-1.35', 'PIT-1.35', 'S-1.35', 'TRST-6',
 'PIT-6', 'ACP-6', 'S-6', 'PIT-18', 'ACP-18', 'S-18', 'PIT-92', 'ACP-92',
 'S-92', 'GSH-1.35', 'GSH-6', 'GSH-18', 'GSH-92', '15MHz', '5MHz', 'FGTCH_SRC']

WINDOW_WIDTH = 14.0
WINDOW_HEIGHT = WINDOW_WIDTH / 1.414286 # to fit A4 paper size
logger.debug("window parameters: %.1f x %.1f inches" %\
              (WINDOW_WIDTH, WINDOW_HEIGHT))
fig, ax = plt.subplots(figsize=(WINDOW_WIDTH, WINDOW_HEIGHT),
                       facecolor='w')
fig.tight_layout(rect=(0.025, 0.01, 0.96, 0.97))
ax.set_xlim([tstart_global, tstop_global])
ax.set_ylim([-len(pars), 0])
ax.set_yticklabels([])
ax.set_yticks([])
ax.set_title('file_name')
x0 = mdates.date2num(tstart_global)
x1 = mdates.date2num(tstop_global)
width = x1 - x0
height = 1
rect_cols = ['white', 'grey']

logger.debug('figure created')

### TS times (Chapters) and some checkings
tctrl0 = [] # times for control parameters
tctrl1 = []
yust_status = [0] * len(chapters[1:])
kk_status = [0] * len(chapters[1:])
i = 0

wrn_cnt = 0

for chapter in chapters[1:]:
    chp = chapter[:300]
    chapter_txt =  ''
    tstart = re.findall('[Ss]tart[\s]*=[\s]*' + '(' + timeptrn + ')', chp)
    tstop =  re.findall('[Ss]top[\s]*=[\s]*'  + '(' + timeptrn + ')', chp)
    tstation = re.findall('TS[\s]*=[\s]*([A-Z,_]*)', chp)
    expcode = re.findall('[Oo]bscode[\s]*=[\s]*'+\
            '([\w]*)', chp)
    if not tstart or not tstop:
        logger.warning("Something wrong with times in block" + \
                           "(skipping):\n[{}".format(chp[:10]))
        continue
    if expcode and expcode[0][:2] in ['Ju', 'ju', 'Yu', 'yu']:
        yust_status[i] = 1
        varyust = re.findall('[Vv]ar[\s]*=[\s]*(\d)', chp)
        if varyust: chapter_txt = 'Var' + varyust[0] + ' '

#        tstart = re.findall('beginscan[\s]*=[\s]*' + '(' + timeptrn + ')',
#                                chapter[:350])
#        tstop = re.findall('endscan[\s]*=[\s]*' + '(' + timeptrn + ')',
#                                chapter[:350])
    prm = re.findall('PRM[\s]*=[\s]*([KCLP]{2})', chp)

#    if expcode:
#        if expcode[0][:4] in ['raks', 'raes', 'rafs', 'rags', 'gbts', 'grts']:
#            shortcode = expcode[0][0] + expcode[0][2] + expcode[0][4:]
#        else:
#            shortcode = expcode[0]
#        chapter_txt = chapter_txt + shortcode + '\n'
#    if tstation:
#        chapter_txt = chapter_txt + tstation[0][:2]
    if prm:
        if prm[0] == 'KK':
            kk_status[i] = 1
        chapter_txt += prm[0]

    for t0, t1 in zip(tstart, tstop):

        if not t0 or not t1:
            logger.error("Something wrong with times in block" + \
                          "(skipping):\n[{}".format(chapter[:290]))
            continue
        t0 = datetime.datetime.strptime(t0, dtfmt)
        t1 = datetime.datetime.strptime(t1, dtfmt)
        t0 = mdates.date2num(t0)
        t1 = mdates.date2num(t1)
        tctrl0.append(t0)
        tctrl1.append(t1)
        ttxt = (t1 + t0)/2.
        ax.text(ttxt, -.5, chapter_txt, ha='center', va='center', size='small')
        ax.axvline(t0, linestyle=':', linewidth=.5, color='darkorange')
        ax.axvline(t1, linestyle=':', linewidth=.5, color='darkorange')
        ax.add_patch(Rectangle((t0, -1), t1-t0, height, alpha=0.7,
                             linewidth=3, facecolor='darkorange'))


### Controls:
# TODO: add advanced control for given receivers configuration
        for ind, t in enumerate(cmdtimes):
            if yust_status[i] == 1:
                continue
            t = mdates.date2num(t)
            if t0 < t < t1:
                if not pars['HET-254'][ind] and not pars['HET-258'][ind]:
                    logger.warning('No FGTCH at {}'.format(mdates.num2date(t)))
                    colors['HET-254'] = 'r'
                    colors['HET-258'] = 'r'
                    wrn_cnt += 1
                    break
                if not pars['VK-1.35'][ind] and not pars['VK-6'][ind] and \
                    not pars['VK-18'][ind] and not pars['VK-92'][ind]:
                    logger.warning('No FGSVCH at {}'.format(mdates.num2date(t)))
                    colors['VK-1.35'] = 'r'
                    colors['VK-6'] = 'r'
                    colors['VK-18'] = 'r'
                    colors['VK-92'] = 'r'
                    wrn_cnt += 1
                    break
                if not pars['POW-1.35'][ind] and not pars['POW-6'][ind] and \
                    not pars['POW-18'][ind] and not pars['POW-92'][ind]:
                    logger.warning('No POWER at {}'.format(mdates.num2date(t)))
                    colors['POW-1.35'] = 'r'
                    colors['POW-6'] = 'r'
                    colors['POW-18'] = 'r'
                    colors['POW-92'] = 'r'
                    wrn_cnt += 1
                if not pars['ADC-6'][ind] and not pars['ADC-18'][ind] and \
                    not pars['ADC-92'][ind] and not kk_status[i]:
                    logger.warning('No ADC at {}'.format(mdates.num2date(t)))
                    colors['ADC-6'] = 'r'
                    colors['ADC-18'] = 'r'
                    colors['ADC-92'] = 'r'
                    wrn_cnt += 1
                if not pars['KEY-1.35'][ind] and not pars['KEY-6'][ind] and \
                    not pars['KEY-18'][ind] and not pars['KEY-92'][ind]:
                    logger.warning('No KEYS at {}'.format(mdates.num2date(t)))
                    colors['KEY-1.35'] = 'r'
                    colors['KEY-6'] = 'r'
                    colors['KEY-18'] = 'r'
                    colors['KEY-92'] = 'r'
                    wrn_cnt += 1
        i += 1


if wrn_cnt:
    warntext = '{} warnings!'.format(wrn_cnt)
else:
    warntext = None

### Plot the data
i = 0
for key in names:
    old_name = old_names[i]
    value = pars[key]
    rcol = rect_cols[(1 + (-1)**(i+1))/2]
    ax.add_patch(Rectangle((x0, -i), width, height, alpha=0.05,
                           fc=rcol, ec='k', lw=2))

    txt_r = ax.text(tstop_global, -i - 0.5, old_name, ha='left', va='center', color=colors[key])
    txt_l = ax.text(tstart_global, -i - 0.5, old_name, ha='right', va='center', color=colors[key])
#    txt_r.set_bbox(dict(color=colors[key], alpha=0.1, edgecolor=None))
#    txt_l.set_bbox(dict(color=colors[key], alpha=0.1, edgecolor=None))

    cond1 = [bool(_==1 or _==3) for _ in value[:]]
    cond2 = [bool(_==2 or _==3) for _ in value[:]]
#    cond3 = [bool(_==2 or _==3) for _ in value[:]]

    if key in ['NG-1.35', 'NG-6', 'NG-18', 'NG-92']:
        ax.fill_between(cmdtimes, -i-1, -i, where=value, facecolor='k', alpha=1)
        i += 1
        continue
    elif key in ['ZU', 'MOD-40W', 'BIK', 'HET-254', 'HET-258', 'VK-1.35',
                 'VK-6', 'VK-18', 'VK-92', '15MHz', '5MHz']:
        ax.fill_between(cmdtimes, -i-1, -i, where=value,
                        facecolor='teal', alpha=0.9)
        i += 1
        continue
    else:
        ax.fill_between(cmdtimes, -i-1, -i-0.5, where=cond2, #hatch = htch[1],
                    facecolor='khaki', alpha=.9)
        ax.fill_between(cmdtimes, -i-0.5, -i, where=cond1, #hatch = htch[2],
                    facecolor='teal', alpha=.9)
#        ax.fill_between(cmdtimes, -i-1, -i, where=cond2, #hatch = htch[2],
#                    facecolor='gold', alpha=.7)
        i += 1


ax.xaxis.set_major_formatter(mdates.DateFormatter('%d.%m %H:%M'))
if warntext is not None:
    ax.set_xlabel(warntext, fontsize=42, color='r')
fig.autofmt_xdate()
ax.set_title(u"{}".format(figfile_base))

plt.show()

fig.savefig(figfile_base + u'.pdf', facecolor='w', edgecolor='w',
        orientation='landscape', papertype='a4', format='pdf',
        transparent=False, bbox_inches=None, pad_inches=-0.5,
        frameon=None)

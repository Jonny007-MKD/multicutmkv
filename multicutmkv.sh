#!/bin/bash

#################################################
# Script zum Schneiden von OTR-Aufnahmen auf Basis von multicut von
# (c) 2006,2007,2008 Hagen Meyer -- hagen@hcmeyer.de
#
# VERSION 130920-r1
# Erweiterungen von Christof Schulze, Lizenz: GPLv2
# VERSION 140624
# Erweiterungen von Jonny007-MKD, Lizenz: GPLv2
#
# https://github.com/Jonny007-MKD/multicutmkv
#################################################
# Exit Codes
#   1 General error or interrupt
#   2 Missing arguments
#   3 Tmp folder not found
#   4 Specified file does not exist
#  10 No cutlist found
#  11 Downloading cutlist failed
#  12 Unknown custlist format
#  20 ffmsindex failed (could not create keyframe list)
#  21 mkvmerge failed
#  22 x264 failed
#   6
#   7
# 126 Additional software needed



#######################
# TODO
#######################
# * Bei Gelegenheit mal die FIXME's durchgehen

#######################
# CONFIG
#######################
# set -ix
# VORSICHT: tempdir wird komplett geleert!! Vorgabewert is empfehlenswert
tempdir="/tmp/multicut"
#tempdir="/mnt/cleartemp/multicut"
# lokale cutlists (aktueller ordner) verwenden? name ist egal, wird nach inhalt ausgewaehlt
# KEIN vorrang vor heruntergeladenen cutlists bei aktiviertem download und automatischem modus
# 0: nein, 1: ja
local=1

# cutlists downloaden?
# versucht alle verfuegbaren cutlists auf cutlist.de zu finden
# 0: nein, 1: ja
download=1

# automatischer modus
# versucht, selbst die beste cutlist zu finden (lokal und internet, je nach einstellung), und verwendet diese.
# im interaktiven modus (automode=0) werden cutlists auch nach qualitaet sortiert, aber die auswahl erfolgt manuell
automode=1

# Mindest-bewertung (vom Autor) fuer cutlists (schlechter wird ignoriert).
#
# Werte:
# 5: framegenau und keine doppelten Szenen
# 4: framegenau
# 3: +/- 1 sek
# < 3: schlechter (wen interessierts? ;) )
#
# Empfehlung: 3-4. Wer will schon ungenaue schnitte??
# (wer mit avisplit schneidet kann auch schlechtere cutlists verwenden, das avisplit eh nur an keyframes schneidet)
min_rating=3

# sollen die schnitte anschliessend mit mplayer ueberprueft werden?
# check=1 oder 0
# mplayer wird nacheinander ca. 10 sekunden vor dem schnitt gestartet. fuer den naechsten schnitt mplayer einfach beenden (mit q)
# anfang und ende werden auch gezeigt
check=0

# Farben - auskommentieren wenn man keine farben moechte
c_filename="\033[00;34m"
c_author="\033[01;37;40m"
c_rating="\033[01;33;41m"
c_cuts="\033[01;33;41m"
c_selection="\033[01;37;40m"
c_error="\033[01;31;40m"
c_info="\033[01;30;42m"
c_end="\033[00m"

function cleanup() 
{
	if [ $# -eq 0 ]; then
		exit 1
	fi
	if [ $1 -eq 0 ]; then		# Delete only when successful
		rm -rf $tempdir
	fi
	exit $1
}

trap 'cleanup' 1 2 3 6 9 13 14 15
# x264 Parameter um HD, HQ und mp4 zu kodieren, wenn smartmkvmerge genutzt
# wird
x264_hd_string="--tune film --direct auto --force-cfr --rc-lookahead 60 --b-adapt 2 --weightp 0"
x264_hq_string="--tune film --direct auto --force-cfr --rc-lookahead 60 --b-adapt 2 --aq-mode 2 --weightp 0"
x264_mp4_string="--force-cfr --profile baseline --preset medium --trellis 0"
X264=x264
X264_X_ARGS=-v
AVCONV=avconv
AVCONV_X_ARGS=
MKVMERGE=mkvmerge
MKVMERGE_X_ARGS=
FFMSINDEX=ffmsindex
FFMSINDEX_X_ARGS=-v
MEDIAINFO=mediainfo
MEDIAINFO_X_ARGS=
# name der avidemux binary. wenn sie nicht automatisch gefunden wird, bitte hier aendern...
if type avidemux3_cli >/dev/null 2>&1 ; then
	avidemux="avidemux3_cli"
elif type avidemux2_cli >/dev/null 2>&1 ; then
	avidemux="avidemux2_cli"
elif type avidemux2 >/dev/null 2>&1; then
	avidemux="avidemux2"
else
	avidemux="avidemux"
fi


#######################
# FUNCTIONS
#######################

x264_opts=""

function check_dependencies1()
{
	local pist=0;
	if ! type gawk >/dev/null 2>&1 ; then
		echo -e "$c_error Please install gawk!" >&2
		pist=1;
	fi
	if ! type bc >/dev/null 2>&1 ; then
		echo -e "$c_error Please install bc!" >&2
		pist=1;
	fi
	if ! type $MEDIAINFO >/dev/null 2>&1 ; then
		echo -e "$c_error Please install mediainfo!" >&2
		pist=1;
	fi

	if [ $pist -ne 0 ]; then
		exit 126;
	fi
}
function check_dependencies2()
{
	local pist=0
	if [ $cutwith == "avidemux" ] && ! type $avidemux > /dev/null 2>&1 ; then
		echo -e "$c_error Please install avidemux!" >&2
		pist=1;
	fi
	if [ $cutwith == "avisplit" ] && ! type avisplit > /dev/null 2>&1 ; then
		echo -e "$c_error Please install 'transcode'!" >&2
		pist=1
	fi
	if [ $cutwith == "smartmkvmerge" ]; then
		if ! type $MKVMERGE > /dev/null 2>&1 ; then
			echo -e "$c_error Please install mkvtoolnix" >&2
			pist=1
		fi
		if ! type $FFMSINDEX > /dev/null 2>&1 ; then
			echo -e "$c_error Please install ffmsindex" >&2
			pist=1
		fi
		if ! type $X264 > /dev/null 2>&1 ; then
			echo -e "$c_error Please install x264" >&2
			pist=1
		fi
		if ! type avxFrameServer > /dev/null 2>&1 ; then
			echo -e "$c_error Please make and install avxsynth" >&2
			pist=1
		fi
	elif [ $cutwith == "smartmkvmerge" ]; then
		if ! type $AVCONV > /dev/null 2>&1 ; then
			echo -e "c_error Please install libav-tools"
			pist=1
		fi
	fi

	if [ $pist -ne 0 ]; then
		exit 126;
	fi
}

function getFtype()
{ # filename
	# setzt einige Variablen in Abhängigkeit vom Dateityp: cutwith und
	# x264_opts
	##############################################################################################
	local filename

	filename=$1
	x264_opts=""

	bt709="--videoformat pal --colorprim bt709 --transfer bt709 --colormatrix bt709"
	bt470bg="--videoformat pal --colorprim bt470bg --transfer bt470bg --colormatrix bt470bg"
	avconvopts="-vcodec mpeg4 -vtag DX50 -q:v 1 -g 300"
	if [ ! -f $filename.mediainfo ]; then
		$MEDIAINFO $MEDIAINFO_X_ARGS $filename > $filename.mediainfo
	fi

	while read line
	do
		case $line in
		"Color primaries"*)
			[[ $line == *"BT.709"* ]] && x264_opts="$x264_opts $bt709"
			[[ $line == *"BT.470"* ]] && x264_opts="$x264_opts $bt470bg" ;;
		"Format profile"*"@L"*) 
			lvl=$(echo ${line#*@L}|cut -d"." -f1); profile=$(echo ${line%@L*}|cut -d":" -f2)
			x264_opts="$x264_opts --level $lvl --profile $profile";;
		"Frame rate mode"*) 
			;;
		"Frame rate"*) 
			fps="$(echo $line |cut -d":" -f2|cut -d" " -f2)"
			x264_opts="$x264_opts --fps $fps";;
		"Encoding settings"*) 
			for opt in $line
			do
				val=${opt#*=}
				case $opt in
					"cabac=0") x264_opts="$x264_opts --no-cabac";;
					"ref="*) x264_opts="$x264_opts --ref $val";;
					"deblock=0"*) x264_opts="$x264_opts --no-deblock";;
					"deblock="*) x264_opts="$x264_opts --deblock ${val:2}";;
					"me="*) x264_opts="$x264_opts --me $val";;
					"subme="*) x264_opts="$x264_opts --subme $val";;
					"psy=0") x264_opts="$x264_opts --no-psy";;
					"psy_rd="*) x264_opts="$x264_opts --psy-rd $val";;
					"mixed-ref=0") x264_opts="$x264_opts --no-mixed-refs";;
					"me_range="*) x264_opts="$x264_opts --merange $val";;
					"chroma_me=0") x264_opts="$x264_opts --no-chroma-me";;
					"trellis="*) x264_opts="$x264_opts --trellis $val" ;;
					"8x8dct=0") x264_opts="$x264_opts --no-8x8dct";;
					"deadzone="*) x264_opts="$x264_opts --deadzone-inter ${val%,*} --deadzone-intra ${val#*,}";;
					"fast_pskip=0") x264_opts="$x264_opts --no-fast-pskip";;
					"chroma_qp_offset="*) x264_opts="$x264_opts --chroma-qp-offset $val";;
					"decimate=0") x264_opts="$x264_opts --no-dct-decimate";;
					"constrained_intra=1") x264_opts="$x264_opts --constrained-intra";;
					"bframes="*)  x264_opts="$x264_opts --bframes $val";;
					"b_pyramid="*) x264_opts="$x264_opts --b-pyramid $val";;
					"b_adapt="*) x264_opts="$x264_opts --b-adapt $val";;
					"b_bias="*) x264_opts="$x264_opts --b-bias $val";;
					"direct=0") x264_opts="$x264_opts --direct none";;
					"direct=1") x264_opts="$x264_opts --direct spatial";;
					"direct=2") x264_opts="$x264_opts --direct temporal";;
					"direct=3") x264_opts="$x264_opts --direct auto";;
					"weightb=0") x264_opts="$x264_opts --no-weightb";;
					"open_gop=1") x264_opts="$x264_opts --open-gop";;
					"weightp="*) x264_opts="$x264_opts --weightp $val";;
					"keyint="*) x264_opts="$x264_opts --keyint $val";;
					"keyint_min="*) x264_opts="$x264_opts --min-keyint $val";;
					"scenecut="*) x264_opts="$x264_opts --scenecut $val";;
					"intra_refresh=1") x264_opts="$x264_opts --intra-refresh";;
					"rc-lookahead="*) x264_opts="$x264_opts --rc-lookahead $val";;
					"mbtree=0") x264_opts="$x264_opts --no-mbtree";;
					"crf="*) x264_opts="$x264_opts --crf $val";;
					"qcomp="*) x264_opts="$x264_opts --qcomp $val";;
					"qpmin="*) x264_opts="$x264_opts --qpmin $val";;
					"qpmax="*) x264_opts="$x264_opts --qpmax $val";;
					"qpstep="*) x264_opts="$x264_opts --qpstep $val";;
					"ip_ratio="*) x264_opts="$x264_opts --ipratio $val";;
					"aq="*) x264_opts="$x264_opts --aq-mode ${val%:*} --aq-strength ${val#*:}";;
					*) ;;
				esac
			done;;
		*) ;;
		esac
	done < $filename.mediainfo

	shopt -s compat31
	# x264 arbeitet nur über ffms genau genug nutze den ffms-demuxer oder leb mit ungenauen Schnitten.
	#x264_opts="$x264_opts --demuxer ffms"
	if [[ ${filename} =~ ".*HQ.avi.*" ]]
	then
		x264_opts="$x264_opts $x264_hq_string"
		cutwith=smartmkvmerge
	elif [[ ${filename} =~ ".*HD.avi.*" ]]; then
		x264_opts="$x264_opts $x264_hd_string"
		cutwith=smartmkvmerge
	elif [[ ${filename} =~ ".*mp4" ]]; then
		x264_opts="$x264_opts $x264_mp4_string"
		cutwith=smartmkvmerge
	else
		x264_opts=""
		cutwith=smartmkvmergeavconv

	fi

	check_dependencies2
}

# Sucht alle cutlists fuer diese gdatei, die beste wird spaeter gesucht...
##############################################################################################
function dlCutlists ()
{ # filename
	cd "$workdir"
	filename="${1}"
	echo -en "$c_info Suche cutlists fuer ${filename##*/}...$c_end"
	if [[ $(uname) != "Linux" ]]
	then
		search=$(stat -f %z "$filename")
		DATE=gdate
	else
		search=$(stat -c %s "$filename")
		DATE=date
	fi

	cd ${tempdir}
	rm *.xml 2>/dev/null # alte xmls loeschen, da sonst keine sichere zuordnung cutlist<->film durgefuehrt werden kann
	# xml herunterladen, und in einzelne abschnitte aufteilen
	#  wget -q -O - "http://cutlist.de/getxml.php?version=0.9.8.0&ofsb=$search" | gawk -F ">" '/<id>/{split($2,tmp,"<");id=tmp[1]}/\/cutlist/{id=0}{if (id>0) {gsub("\t","");print > id ".de.xml" }}'

	wget -q -O - "http://cutlist.at/getxml.php?ofsb=$search" | gawk -F ">" '/<id>/{split($2,tmp,"<");id=tmp[1]}/\/cutlist/{id=0}{if (id>0) {gsub("\t","");print > id ".at.xml" }}'
}

function dlCutlist ()
{ # array-index
	cd $tempdir
	idx=$1
	wget -q -O "${cutlist[$idx]}" "${url[$idx]}"
	# "FIELD": Cutlist-Format
	if [ ! -f "${cutlist[$idx]}" ]; then
		echo -e "$c_error Dowloading cutlist failed!" >&2
		cleanup 11
	fi
	if grep -q "StartFrame=" "${cutlist[$idx]}" ; then
		vcf2format[$idx]=1
	elif grep -q "Start=" "${cutlist[$idx]}" ; then
		vcf2format[$idx]=0
	else
		echo -e "$c_error unbekanntes Cutlist-Format: ${cutlist[$idx]}" >&2
		cleanup 12
	fi
}

# sucht die beste cutlist fuer eine gdatei aus dem ordner $tempdir
#############################################################
function findBestCutlist ()
{ # filename
	echo "Filtere Cutlists nach gegebenen Kriterien..."
	cd $tempdir
	unset cutlist
	# echo $(ls)
	filename="${1##*/}"
	filename="${filename%TVOON*}"
	i=1
	# Lade die wichtigen daten der passenden cutlists in arrays (cutlist, rating, cuts)
	# beruecksichtigt vorerst nur LOKALE cutlists, online kommt spaeter
	for cl in $(find . -type f ! -size +1M -exec grep -qi ApplyToFile=$filename {} \; -print)
	do
		unset url[$i]
		# FIELD: RatingByAuthor
		tmp=$(grep RatingByAuthor $cl)
		tmp=${tmp%[[:cntrl:]]} # letztes zeichen loeschen (\r)
		rating[$i]=${tmp#RatingByAuthor=}
		[ ${rating[$i]} -lt $min_rating ]  && continue	# naechste cutlist, wenn rating zu gering
		# "FIELD": Cutlist-Format
		if grep -q "StartFrame=" $cl ; then
			vcf2format[$i]=1
		elif grep -q "Start=" $cl ; then
			vcf2format[$i]=0
		else
			echo -e "$c_error Unbekanntes Cutlist-Format: ${cl##*/}" >&2
			continue # cutlist ignorieren, unbekanntes format...
		fi
		# FIELD: Author
		tmp=`grep "^Author" $cl`
		tmp=${tmp%[[:cntrl:]]}
		author[$i]=${tmp#Author=}
		author[$i]=${author[$i]:-Unbekannt}
		# FIELD: NoOfCuts
		tmp=`grep NoOfCuts $cl`
		tmp=${tmp%[[:cntrl:]]} # letztes zeichen loeschen (\r)
		cuts[$i]=${tmp#NoOfCuts=}
		echo "$tmp"
		# FIELD: Comment
		tmp=`grep UserComment $cl`
		tmp=${tmp%[[:cntrl:]]} # letztes zeichen loeschen (\r)
		comment[$i]=${tmp#UserComment=}
		# verschiedene fehler...
		unset error[$i] content[$i] errordesc[$i]
		if grep -q "EPGError=1" $cl ; then
			tmp=`grep ActualContent $cl`
			tmp=${tmp%[[:cntrl:]]} # letztes zeichen loeschen (\r)
			content[$i]="Tatsaechlicher Inhalt: ${tmp#ActualContent=}"
			error[$i]=" EPG-Fehler! "
		fi
		if grep -q "MissingBeginning=1" $cl ; then
			error[$i]="${error[$i]} Anfang fehlt! "
		fi
		if grep -q "MissingEnding=1" $cl ; then
			error[$i]="${error[$i]} Ende fehlt! "
		fi
		if grep -q "MissingAudio=1" $cl ; then
			error[$i]="${error[$i]} Ton fehlt! "
		fi
		if grep -q "MissingVideo=1" $cl ; then
			error[$i]="${error[$i]} Bild fehlt! "
		fi
		if grep -q "OtherError=1" $cl ; then
			tmp=`grep OtherErrorDescription $cl`
			tmp=${tmp%[[:cntrl:]]} # letztes zeichen loeschen (\r)
			errordesc[$i]="Fehlerbeschreibung: ${tmp#OtherErrorDescription=}"
			error[$i]="${error[$i]} Sonstiger Fehler! "
		fi

		# Nicht vergessen: dateiname
		cutlist[$i]=${cl##*/}
		# userrating
		if [ -f "${cutlist[$i]}.rating" ] ; then
			userrating[$i]=$( cat "${cutlist[$i]}.rating" )
		else
			unset userrating[$i]
		fi
		# erst hier increment, vorher kann das speichern dieser cutlist abgebrochen werden
		let i++
	done

	# nun zu den ONLINE cutlists...
	shopt -s nullglob
	for cl in *.xml
	do
		unset error[$i] content[$i] errordesc[$i] vcf2format[$i]
		# FIELD: RatingByAuthor
		tmp=`grep "<ratingbyauthor>" $cl`
		tmp=${tmp%<*}
		rating[$i]=${tmp#*>}
		[ ${rating[$i]} -lt $min_rating ]  && continue	# naechste cutlist, wenn rating zu gering
		# FIELD: Author
		tmp=`grep "<author>" $cl`
		tmp=${tmp%<*}
		author[$i]=${tmp#*>}
		author[$i]=${author[$i]:-Unbekannt}
		# FIELD: cuts (noch nicht unterstuetzt)
		cuts[$i]="0"
		# FIELD: Comment
		tmp=`grep "<usercomment>" $cl`
		tmp=${tmp%<*}
		comment[$i]=${tmp#*>}
		# EPG-Fehler!
		tmp=`grep "<actualcontent>" $cl`
		tmp=${tmp%<*}
		tmp=${tmp#*>}
		if [ -n "$tmp" ]; then
			content[$i]="Tatsaechlicher Inhalt: ${tmp#ActualContent=}"
			error[$i]=" EPG-Fehler! "
		fi
		# FIELD: userrating
		tmp=`grep "<rating>" $cl`
		tmp=${tmp%<*}
		tmp=${tmp#*>}
		if [ -n "$tmp" ]; then
			userrating[$i]=$tmp
			tmp=`grep "<ratingcount>" $cl`
			tmp=${tmp%<*}
			userrating[$i]="${userrating[$i]}|${tmp#*>}"
		else
			unset userrating[$i]
		fi
		# gdateiname
		tmp=`grep "<name>" $cl`
		tmp=${tmp%<*}
		cutlist[$i]=${tmp#*>}
		# url
		cl=${cl##*/}
		cl=${cl%.*}
		url[$i]="http://cutlist.${cl#*.}/getfile.php?id=${cl%.*}"
		let i++
	done

	if [ ${#cutlist[@]} -eq 0 ] ; then
		echo -e "$c_error Keine passende Cutlist fuer $c_filename$filename$c_error gefunden. Abbruch.$c_end" >&2
		return 0
	fi
	sortCutlists		# gesammelte cutlists nach "qualitaet" sortieren
	(( $automode > 0 )) && return 1	# interaktive auswahl nicht noetig, ersten eintrag der arrays verwenden
	# interaktive auswahl...
	clear
	echo -e "\n$c_info Fuer die Datei $c_filename$filename$c_end wurden folgende cutlists gefunden:$c_end\n\n"
	i=2
	#  while [ $i -le ${#cutlist[@]} ] ; do
	for ((i=0;i<=${#cutlist[@]};i++))
	do
		if [ -z "${vcf2format[$i]}" ] ; then
			format_string="Unbekannt"
		else
			format_string=$( [ ${vcf2format[$i]} -eq 1 ] && echo "VCF2Cutlist-Standard" || echo "Assistant-Standard" )
		fi
		printf "$c_selection[%d]$c_end\t%s von $c_author %s $c_end\n\tAutor-Wertung: $c_rating %d $c_end\t\tUser-Wertung: $c_rating %s $c_end (%d Stimmen)\n\tFormat: %s\tAnzahl Schnitte: $c_cuts %d $c_end\n\tKommentar: %s\n" $((i+1)) "${cutlist[$i]}" "${author[$i]}" "${rating[$i]}" "${userrating[$i]%|*}" "${userrating[$i]#*|}" "$format_string" "${cuts[$i]}" "${comment[$i]}"
		if [ -n "${error[$i]}" ] ; then
			echo -e "\t$c_error${error[$i]}$c_end" >&2
		fi
		if [ -n "${content[$i]}" ] ; then
			echo -e "\t${content[$i]}"
		fi
		if [ -n "${errordesc[$i]}" ] ; then
			echo -e "\t${errordesc[$i]}"
		fi
		if [ -n "${url[$i]}" ] ; then
			echo -e "\t$c_info Online - ${url[$i]%/*} $c_end"
		fi
		echo
		#  let i++
	done
	printf "$c_selection[0]$c_end\tKeine Auswahl. Diesen Film nicht schneiden.\n\n\n"
	read -p "Auswahl: " ret
	# FIXME hier koennte noch ein plausi-check erfolgen...
	return $ret
}

# sortiere cutlists nach "qualitaet" (absteigend): RatingByAuthor->User-Rating->VCF2Format?->NoOfCuts->ActualContent
##########################################################################################
# Erklaerung:
# RatingByAuthor gibt die beste Auskunft der Schnittqualitaet
# VCF2Format schneidet nach Frames, nicht nach zeit ==> duerfte meistens besser sein
# Mehr Cuts duerfte meistens besser sein, (ueberschuessiges Ende weg, keine Werbung uebersehen, etc.)
# ActualContent: wenn leer, dann besser (meistens gesetzt, wenn es nicht um den eigentlich aufgenommenen film geht,
# sondern um das ende des vorhergehenden o.ae.
# !! vollautomatisch kann NIE die absolut beste cutlist gefunden werden, es ist nur der versuch eine moeglichst gute zu finden...
##########################################################################################
function sortCutlists ()
{ # greift auf die arrays zu, die in "findBestCutlist" erstellt werden
	local changed=1
	while [ $changed -eq 1 ] ; do
		changed=0
		i=2
		while [ $i -le ${#cutlist[@]} ] ; do
			if [ ${rating[$i-1]} -lt ${rating[$i]} ] ; then
				swap $i
				changed=1
			elif [ ${rating[$i-1]} -eq ${rating[$i]} ] && [ "${userrating[$i-1]%|*}" \< "${userrating[$i]%|*}" ] ; then
				swap $i
				changed=1
			elif [ ${rating[$i-1]} -eq ${rating[$i]} ] && [ "${userrating[$i-1]%|*}" = "${userrating[$i]%|*}" ] && [ ${vcf2format[$i-1]:-0} -lt ${vcf2format[$i]:-0} ] ; then
				swap $i
				changed=1
			elif [ ${rating[$i-1]} -eq ${rating[$i]} ] && [ "${userrating[$i-1]%|*}" = "${userrating[$i]%|*}" ] && [ ${vcf2format[$i-1]:-0} -eq ${vcf2format[$i]:-0} ] && [ ${cuts[$i-1]} -lt ${cuts[$i]} ] ; then
				swap $i
				changed=1
			elif [ ${rating[$i-1]} -eq ${rating[$i]} ] && [ "${userrating[$i-1]%|*}" = "${userrating[$i]%|*}" ] && [ ${vcf2format[$i-1]:-0} -eq ${vcf2format[$i]:-0} ] && [ ${cuts[$i-1]} -eq ${cuts[$i]} ] && [ -z "${content[$i]}" ] && [ -n "${content[$i-1]}" ]; then
				swap $i
				changed=1
			fi
			let i++
		done
	done
}

function swap ()
{ # parameter: i: elemente i-1 und i werden (von allen arrays) vertauscht
	local tmp="${cutlist[$1-1]}"
	cutlist[$1-1]="${cutlist[$1]}"
	cutlist[$1]="$tmp"
	tmp="${rating[$1-1]}"
	rating[$1-1]="${rating[$1]}"
	rating[$1]="$tmp"
	tmp="${userrating[$1-1]}"
	userrating[$1-1]="${userrating[$1]}"
	userrating[$1]="$tmp"
	tmp="${vcf2format[$i-1]}"
	vcf2format[$i-1]="${vcf2format[$i]}"
	vcf2format[$i]="$tmp"
	tmp="${cuts[$1-1]}"
	cuts[$1-1]="${cuts[$1]}"
	cuts[$1]="$tmp"
	tmp="${comment[$1-1]}"
	comment[$1-1]="${comment[$1]}"
	comment[$1]="$tmp"
	tmp="${content[$1-1]}"
	content[$1-1]="${content[$1]}"
	content[$1]="$tmp"
	tmp="${author[$1-1]}"
	author[$1-1]="${author[$1]}"
	author[$1]="$tmp"
	tmp="${error[$1-1]}"
	error[$1-1]="${error[$1]}"
	error[$1]="$tmp"
	tmp="${errordesc[$1-1]}"
	errordesc[$1-1]="${errordesc[$1]}"
	errordesc[$1]="$tmp"
	tmp="${url[$1-1]}"
	url[$1-1]="${url[$1]}"
	url[$1]="$tmp"
}

function findclosesttime()
{
	# this will show the time matching a frame that is closest to the time that
	# is passed as parameter
	local film
	local millis
	local kflist

	millis=$1
	film=$2
	kflist="${film##*/}.ffindex_track00.tc.txt"
	if [ ! -f "${kflist}" ]
	then
		$FFMSINDEX $FFMSINDEX_X_ARGS -k -p -c -f $film ${film##*/}.ffindex
		if [ ! -f "${kflist}" ]; then
			echo -e "$c_error ffmsindex failed" >&2
			cleanup 20
		fi
	fi
	echo $millis >> millis
	danach=$(cat millis $kflist|grep -v "#"| sort -n | grep -A 1 $millis |tail -n1)
	davor=$(cat millis $kflist|grep -v "#"| sort -n | grep -B 1 $millis |head -n1)

	if [[ $(echo "$danach - $millis"|bc -l|sed 's/\.//') -gt $(echo "$millis - $davor"|bc -l |sed 's/\.//') ]]
	then
		echo $danach
	else
		echo $davor
	fi
}

function findkeyframeafterframe()
{
	# this will show the keyframe that is after the current frame
	local film
	local frame

	frame=$1
	film=$2
	local kflist
	kflist="${film##*/}.ffindex_track00.kf.txt"
	if [ ! -f "${kflist}" ]
	then
		$FFMSINDEX $FFMSINDEX_X_ARGS -k -p -c -f $film ${film##*/}.ffindex
		if [ ! -f "${kflist}" ]; then
			echo -e "$c_error ffmsindex failed" >&2
			cleanup 20
		fi
	fi
	echo $frame > frame
	keyframe=$(cat frame $kflist|grep -v "#"| sort -n | grep -A 1 "^${frame}$" |tail -n1)
	case $keyframe in
	*#*) keyframe=0;;
	esac
	echo $keyframe
}

function iskeyframe()
{
	# this will return 0 if the current frame is a keyframe
	local film
	local frame
	local kflist
	frame=$1
	film=$2
	kflist="${film##*/}.ffindex_track00.kf.txt"
	if [ ! -f "${kflist}" ]
	then
		$FFMSINDEX $FFMSINDEX_X_ARGS -k -p -c -f $film ${film##*/}.ffindex
		if [ ! -f "${kflist}" ]; then
			echo -e "$c_error ffmsindex failed" >&2
			cleanup 20
		fi
	fi
	grep -q "^${frame}$" $kflist
	return $?
}

function convertframestostime () 
{
	local film
	local frame
	local timev
	local list
	frame=$2
	film=$1

	list="${film##*/}.ffindex_track00.tc.txt"
	if [ ! -f "${list}" ]
	then
		$FFMSINDEX $FFMSINDEX_X_ARGS -k -p -c -f $film ${film##*/}.ffindex
		if [ ! -f "${kflist}" ]; then
			echo -e "$c_error ffmsindex failed" >&2
			cleanup 20
		fi
	fi
	local tmp
	timev=$(awk "NR==$((frame+2)) {print;exit}"  $list)
	echo "$timev / 1000"|bc -l
}


function findkeyframebeforeframe()
{
	# this will show the keyframe that is before the current frame
	local film
	local frame
	local keyframe 
	frame=$1
	film=$2
	local kflist
	kflist="${film##*/}.ffindex_track00.kf.txt"
	if [ ! -f "${kflist}" ]
	then
		$FFMSINDEX $FFMSINDEX_X_ARGS -k -p -c -f $film ${film##*/}.ffindex
		if [ ! -f "${kflist}" ]; then
			echo -e "$c_error ffmsindex failed" >&2
			cleanup 20
		fi
	fi
	echo $frame > frame
	keyframe=$(cat frame $kflist|sort -n| grep -B 1 "^${frame}$" | head -n1)
	case $keyframe in
	*#*) keyframe=0;;
	esac
	echo $keyframe
}

function get_timecode()
{
	# convert a string with second.subsecond to hh:mm:ss:SSSSSSSS
	local tmp
	local subsec
	tmp=$1
	subsec=${tmp#*.}
	subsec=${subsec:0:7}
	echo -e "$($DATE -u -d @${tmp} +%T).${subsec:-0}"
}

# schneide datei mit gegebener cutlist
########################################################################
function cutfilm ()
{ # film, cutlist, vcf2format?
	film="$1"
	cutlist="$2"
	vcf2format="$3"
	cuts=""
	unset checktimes
	checktimes[0]=0
	checkcnt=0
	unset markerA
	unset markerB
	markercnt=0
	markersminus=0
	markerA[0]=0
	cd "$tempdir"
	if ! [ $(echo $film|grep -qv "\.mkv" ) ]
	then
		if [ $cutwith == "avidemux" ] || [ $cutwith == "smartmkvmergeavconv" ]
		then
			if [ ! -f "${tempdir}/mkv.ok" ]; then
				$MKVMERGE $MKVMERGE_X_ARGS -o "${tempdir}/$(basename $film).mkv" "$film"
				if [ $? -eq 0 ]; then
					touch "${tempdir}/mkv.ok"
				else
					echo -e "$c_error mkvmerge failed" >&2
					cleanup 21
				fi
			fi
			film="${tempdir}/$(basename $film).mkv"
			if [ ! -f $film ]; then
				echo -e "$c_error mkvmerge failed" >&2
				cleanup 21
			fi
		fi
	fi

	project_start "$film"
	getFtype $film
	lines=$( egrep "^(Start|Duration)=" "$cutlist" | tr -d "\r" )
	fps=$( grep FramesPerSecond "$cutlist" | tr -d "\r" | sed 's/FramesPerSecond=//' )
	for line in $lines ; do
		if echo $line | grep -q "Start" ; then  ######### startcut ##########
		startcut="${line##*=}"
		secs="${startcut%%.*}"
		decimalsecs=$[ 10#${startcut##*.} ]
		decimalsecs=${decimalsecs::2}

		frames=`echo "$startcut * $fps + 0.5" | bc` # +0.5 zum runden...
		frames=${frames%%.*}
		sframe=$frames
		sdecimalsecs=$decimalsecs

 

		if [ $cutwith == "avidemux" ]; then
			avidemillis=$(echo "$startcut*1000"|bc -l)
			millis=$( findclosesttime ${avidemillis} $film)
			echo -n "adm.addSegment(0, $millis, " >> project.py
		elif [ $cutwith == "avisplit" ] ; then
			time=$( $DATE -u -d @$secs +%T )		# wandelt sekunden.dezimalen in hh:mm:ss um...
			frames=$(( ${decimalsecs:-0} / 4 ))		# frames ausrechnen runden ist egal
			cuts=$cuts$time.$frames-			# hh:mm:ss.ms (ms ist frames, nicht millisekunden!!)
		elif [ $cutwith == "smartmkvmergeavconv" ] ; then
			echo -n ""
		elif [ $cutwith == "smartmkvmerge" ] ; then
			echo -n ""
		else
			markerB[$markercnt]=$(( $secs*25 + ${decimalsecs:-0} / 4 - $markersminus))
			let markersminus=$markersminus+${markerB[$markercnt]}-${markerA[$markercnt]}
			let markercnt++
		fi
		else					######### endcut ############
			length="${line##*=}"
			if [ $cutwith == "avisplit" ] ; then
				add_decimal $startcut ${line##*=}
				time=$( $DATE -u -d @$solution +%T )
				decimalsecs=${solution##*.}
				decimalsecs=${decimalsecs::2}
				decimalsecs=${decimalsecs#2}
				frames=$(( ${decimalsecs:-0} / 4 ))
				cuts=$cuts$time.$frames,
			else
				frames=`echo "$length * $fps + 0.5 " | bc` # +0.5 zum runden...
				frames=${frames%%.*}

				if [ $cutwith == "avidemux" ] ; then
					tmp=$(echo "$avidemillis+(${length}*1000)"|bc -l)
					echo "findclosesttime $tmp)"
					# millis=$( findclosesttime $((secs+${length%.*}))$((sdecimalsecs/1000 + decimalsecs/1000)).$((sdecimalsecs % 1000 * 1000 + decimalsecs%1000 * 1000)) $film)
					millis=$( findclosesttime $tmp $film)
					echo "${millis})" >> project.py  
				elif [ $cutwith == "smartmkvmerge" ] || [ $cutwith == "smartmkvmergeavconv" ]; then
					echo "$length $startcut"
					tmp=$(echo "${startcut} + ${length}"|bc -l)
					audio_timecodes="${audio_timecodes},+$(get_timecode $startcut)-$(get_timecode $tmp)"
					#	  echo startframe: $sframe
					#	  echo duration: $frames # endframe
					skeyframe=$(findkeyframebeforeframe $sframe $film)
					local tmp
					# encode
					echo -e "$c_info start: $sframe"
					echo -e "end: $frames$c_end"

					if iskeyframe $sframe $film; then
						echo start ist keyframe
						if iskeyframe $((sframe + frames)) $film; then
							echo end ist keyframe
							# das gesamte geforderte Häppchen endet und beginnt auf keyframes
							# FIXME - Beschränkung: maximal 9 Cuts sind so pro Film möglich.
							video_splitframes="${video_splitframes},$sframe-$((sframe + frames))"
							video_files[${#video_files[@]}]=video_copy-00${checkcnt}.mkv
						else
							echo end ist kein keyframe
							# das häppchen startet mit keyframe aber endet nicht aufkeyframe
							lkeyframe=$(findkeyframebeforeframe $((sframe + frames)) $film)
							ulkeyframe=$lkeyframe
							if (( $lkeyframe < $sframe )); then
								ulkeyframe=$sframe
							fi
							# FIXME - Beschränkung: maximal 9 Cuts sind so pro Film möglich.
							video_files[${#video_files[@]}]=video_copy-00${checkcnt}.mkv
							outputfilename=cut${checkcnt}_seg3.mkv

							if [ $cutwith == "smartmkvmerge" ] && [ ! -f $outputfilename.ok ] ; then
								$X264 $X264_X_ARGS $x264_opts --index ${tempdir}/x264.index --seek $lkeyframe --frames $((frames-ulkeyframe+sframe)) --output $outputfilename $film
								if [ $? -ne 0 ] || [ ! -f $outputfilename ] || [ $(stat -c %s "$outputfilename") -eq 0 ]; then
									echo -e "$c_error x264 failed" >&2
									cleanup 22
								else
									touch $outputfilename.ok
								fi
							elif [ $cutwith == "smartmkvmergeavconv" ]; then
								# TODO richtige Start und endwerte prüfen
								avstime=$(convertframestostime "$film" $lkeyframe)
								preseek=0
								if (( ${avstime%.*} > 31 ))
								then
									preseek=$(echo ${avstime%.*}-30|bc)
								fi
								avstime=$(echo ${avstime} - $preseek| bc -l )
								$AVCONV $AVCONV_X_ARGS -ss $preseek -i "${film}"  -ss $avstime $avconvopts -vframes $((frames-ulkeyframe+sframe))   ${outputfilename}.avi
								$MKVMERGE $MKVMERGE_X_ARGS -o "${outputfilename}" "${outputfilename}.avi"
							fi
							video_files[${#video_files[@]}]=$outputfilename
							video_splitframes="${video_splitframes},$sframe-$lkeyframe"
						fi
					else
						echo start ist kein keyframe
						asframe=$(findkeyframeafterframe $sframe $film)
						eframes=$((asframe-sframe))
						if (( $asframe  > $sframe + $frames )); then
							eframes=$frames
						fi
						outputfilename=cut${checkcnt}_seg1.mkv
						if [ $cutwith == "smartmkvmerge" ] && [ ! -f $outputfilename.ok ] ; then
							$X264 $X264_X_ARGS $x264_opts --index ${tempdir}/x264.index --seek $sframe --frames $((eframes)) --output $outputfilename $film
							if [ $? -ne 0 ] || [ ! -f $outputfilename ] || [ $(stat -c %s "$outputfilename") -eq 0 ]; then
								echo -e "$c_error x264 failed" >&2
								cleanup 22
							else
								touch $outputfilename.ok
							fi
						elif [ $cutwith == "smartmkvmergeavconv" ]; then
							# TODO richtige Start und endwerte prüfen
							avstime=$(convertframestostime "$film" $sframe)
							preseek=0
							if (( ${avstime%.*} > 31 )); then
								preseek=$(echo ${avstime%.*}-30|bc)
							fi
							avstime=$(echo ${avstime} - $preseek| bc -l )
							$AVCONV $AVCONV_X_ARGS -ss $preseek -i "${film}"  -ss $avstime $avconvopts -vframes $((eframes)) ${outputfilename}.avi
							$MKVMERGE $MKVMERGE_X_ARGS -o "${outputfilename}" "${outputfilename}.avi"
						fi

						video_files[${#video_files[@]}]=$outputfilename

						if iskeyframe $((sframe + frames)) $film; then
							echo end ist keyframe
							# start ist kein keyframe aber ende
							if (($frames+$sframe > $asframe )); then
								video_splitframes="${video_splitframes},$asframe-$((frames+sframe))"
								# FIXME - Beschränkung: maximal 9 Cuts sind so pro Film möglich.
								video_files[${#video_files[@]}]=video_copy-00${checkcnt}.mkv
							fi
						else
							echo end ist kein keyframe
							# weder start noch ende sind keyframes
							if (($frames+$sframe > $asframe )); then
								beframe=$(findkeyframebeforeframe $((sframe + frames)) $film)
								if (( $beframe  > $asframe )); then
									video_splitframes="${video_splitframes},$asframe-$beframe"
									# FIXME - Beschränkung: maximal 9 Cuts sind so pro Film möglich.
									video_files[${#video_files[@]}]=video_copy-00${checkcnt}.mkv
								fi
								outputfilename=cut${checkcnt}_seg3.mkv


								if [ $cutwith == "smartmkvmerge" ] && [ ! -f $outputfilename.ok ] ; then
									$X264 $X264_X_ARGS $x264_opts  --index ${tempdir}/x264.index --seek $beframe --frames $((sframe+frames-beframe)) --output $outputfilename $film
									if [ $? -ne 0 ] || [ ! -f $outputfilename ] || [ $(stat -c %s "$outputfilename") -eq 0 ]; then
										echo -e "$c_error x264 failed" >&2
										cleanup 22
									else
										touch $outputfilename.ok
									fi
								elif [ $cutwith == "smartmkvmergeavconv" ]; then
									# TODO richtige Start und endwerte prüfen
									avstime=$(convertframestostime "$film" $beframe)
									preseek=0
									if (( ${avstime%.*} > 31 )); then
										preseek=$(echo ${avstime%.*}-30|bc)
									fi
									avstime=$(echo ${avstime} - $preseek| bc -l )
									echo $sframe $frames $beframe
									$AVCONV $AVCONV_X_ARGS -ss $preseek -i "${film}"  -ss $avstime $avconvopts  -vframes $((sframe+frames-beframe)) ${outputfilename}.avi
									$MKVMERGE $MKVMERGE_X_ARGS -o "${outputfilename}" "${outputfilename}.avi"
								fi	
								video_files[${#video_files[@]}]=$outputfilename
							fi
						fi
					fi
				else
					let markerA[$markercnt]=${markerA[$markercnt-1]}+$frames
				fi
			fi
			let checkcnt++
			checktimes[$checkcnt]=$((${checktimes[$checkcnt-1]}+${length%%.*}))
		fi
	done

	markerB[$markercnt]="ENDE"
	name="${film##*/}"
	outname="$cutdir/${name%.mpg.avi}-cut.avi"

	if [ $cutwith == "smartmkvmerge" ] || [ $cutwith == "smartmkvmergeavconv" ]; then
		outname="$cutdir/${name%.mpg.avi}-cut.mkv"
		video_splitframes="${video_splitframes:1}"
		audio_timecodes="${audio_timecodes:2}"
		[[ $cutwith == "smartmkvmerge" ]] && mkvmergeopts="-A"
		$MKVMERGE $MKVMERGE_X_ARGS --ui-language en_US --split parts-frames:$video_splitframes $mkvmergeopts -o video_copy.mkv $film

		vcopy=( video_copy*.mkv )
		vindex=0
		for ((i=0;i<${#video_files[@]};i++))
		do
			case ${video_files[i]} 
			in
			video_copy*) vfiles="${vfiles} +${vcopy[$vindex]}";((vindex+=1));;
			*) vfiles="${vfiles} +${video_files[i]}";;
			esac
		done
		vfiles="${vfiles:2}"

		afiles=""
		if [ $cutwith == "smartmkvmerge" ]; then
			# audiostream kopieren
			$MKVMERGE $MKVMERGE_X_ARGS --ui-language en_US -D --split parts:$audio_timecodes -o  audio_copy.mkv $film
			afiles=audio_copy*.mkv
			mkvmergeopts="-D"
		fi
		# mux
		$MKVMERGE $MKVMERGE_X_ARGS --engage no_cue_duration --engage no_cue_relative_position --ui-language en_US -o $outname ${vfiles} ${afiles}
		ecode=$?
		if (( $ecode < 2 )) && [ -f "$outname" ] ; then
			echo "$name erfolgreich geschnitten!"
			if (( $ecode == 1 )) 
			then
				echo "mkvmerge hat Warnungen ausgegeben - bitte Ausgabedatei auf Abspielbarkeit prüfen."
			fi
		else
			echo "Es ist Fehler $ecode aufgetreten! $name moeglicherweise nicht geschnitten!"
			cleanup 21
		fi
	elif [ $cutwith == "avisplit" ] ; then
		cuts=${cuts%,}	# letztes komma abtrennen...
		echo "Uebergebe die errechneten Cuts an avisplit..."
		echo avisplit -i $film -o "$outname" -t $cuts -c
		# Auftrag an avisplit uebergeben... (mergen wird hier durch -c auch erreicht)
		avisplit -i "$film" -o "$outname" -t $cuts -c >/dev/null
		if [ $? -eq 0 ] ; then
			echo "$name erfolgreich geschnitten!"
		else
			echo "Avisplit hat einen Fehler gemeldet! $name moeglicherweise nicht geschnitten!"
			return
		fi
	else # zeige stellen zum schneiden an
		echo "Jede nachfolgende Zeile steht fuer einen Werbeblock (Frameposition). Positionieren Sie die Marker, und optimieren Sie ihre Position."
		echo "Die nachfolgende Zeile gibt die Frameposition NACH dem herausschneiden aller vorherigen Bloecke an."
		echo
		cnt=0
		while [ $cnt -le $markercnt ] ; do
			echo -e "A: ${markerA[$cnt0]}\t B: ${markerB[$cnt]}"
			let cnt++
		done
		echo
		echo "Bitte stellen Sie Ihre verbesserte Cutlist auf http://cutlist.de zur Verfuegung, die Community kann nur funktionieren, wenn alle mitarbeiten!"
		echo
	fi
	## schnittstellen ueberpruefen
	[ $check -eq 1 ] && type mplayer >/dev/null && read -p "Zur Ueberpruefung der Schnittstellen bitte Taste druecken..." -n 1
	echo "Schnitte bei folgenden Zeiten:"
	i=0
	while [ $i -lt ${#checktimes[@]} ] ; do
		$DATE -u -d @${checktimes[$i]} +%T
		[ $check -eq 1 ] && type mplayer >/dev/null && mplayer -osdlevel 3 -ss $(( ${checktimes[$i]} - 10 )) "$outname" 1>/dev/null 2>/dev/null
		let i++
	done
}

function project_start () { # film
	cat <<HEADER > project.py
	#PY  <- Needed to identify #

	adm = Avidemux()
	adm.loadVideo("$1")
	adm.clearSegments()
HEADER
}

function project_end () { # save-as
	cat <<FOOTER >> project.py
	adm.videoCodec("Copy")
	adm.audioClearTracks()
	adm.audioAddTrack(0)
	adm.audioCodec(0, "copy");
	adm.audioSetDrc(0, 0)
	adm.audioSetShift(0, 0,0)
	adm.setContainer("MKV", "forceDisplayWidth=False", "displayWidth=1280")
FOOTER
}

# dezimales addieren
########################
function add_decimal ()
{ # zahl1, zahl2, ==> ergebnis in $solution
	int1=${1%.*}
	int2=${2%.*}
	let ret_int=$int1+$int2
	dec1=${1#*.}
	dec2=${2#*.}
	while [ ${#dec1} -lt ${#dec2} ] ; do		# solange die erste zahl "kuerzer" ist...
		dec1=${dec1}0
	done
	while [ ${#dec2} -lt ${#dec1} ] ; do		# umgekehrt...
		dec2=${dec2}0
	done
	length=${#dec1}				# maximale laenge der nachkommastellen
	shopt -s extglob
	dec1=${dec1#*[0]}				# fuehrende nuller entfernen
	dec1=${dec1:-0}				# und sicherstellen, dass nicht leer
	dec2=${dec2#*[0]}
	dec2=${dec2:-0}
	let ret_dec=$dec1+$dec2
	if [ ${#ret_dec} -gt $length ] ; then		# laenger, also uebertragen
		let ret_int++
		ret_dec=${ret_dec#1}
	fi
	solution=$ret_int.$ret_dec
}

function help () {
cat <<END
Aufruf: ${0##*/} [-x|-sm|-n|-s] [-l|-nl] [-d|-nd] [-c|-nc] [-o <Ausgabepfad>] [-i|-a] [-m <Bewertung>] <Datei>

Moegliche Optionen:

-x	Avidemux verwenden - 2.5, framegenau aber HQ und HD mit Artefakten,
2.6 grundsätzlich Artefakte an Schnittpunkten
-sm	smartmkv verwenden - geht nur für HQ, HD und mp4, framegenau
-n	nicht schneiden, nur Schnittstellen anzeigen - zum manuellen Verbessern der Schnitte, deaktiviert ueberpruefen
-s	Avisplit für Schnitt an keyframes verwenden

-l	Lokale Cutlists einbeziehen
-nl	Lokale Cutlists NICHT einbeziehen
-d	Cutlists downloaden
-nd	Cutlists NICHT downloaden
-c	Schnittstellen ueberpruefen - erfordert mplayer
-nc	Schnittstellen NICHT ueberpruefen
-o	Ausgabeverzeichnis

-i	Interaktiver Modus
-a	Automatischer Modus - kein manuelle cutlist auswahl

-m X	verwerfe Cutlists mit Bewertungen schlechter als X - Wete zwischen 0 bis 5

Optionen muessen VOR den Dateien angegeben werden, wenn Optionen einen Parameter verlangen muss dieser ZWINGEND angegeben werden. Das Script fuehrt KEINE Ueberpruefung der Argumente durch, falsche Argumente koennen zu Fehlern fuehren!

Die Standard-Optionen koennen am Anfang des Scripts eingestellt werden. Dort sind die einzelnen Optionen auch nochmal genauer beschrieben.

(c) 2006-2007 Hagen Meyer <hagenmeyer@web.de>
END
cleanup 1
}

#######################
# START
#######################

check_dependencies1

# guess a decent default for cutwith
if [[ ${@} =~ ".*HQ.avi.*" ]]
then
	cutwith=smartmkvmerge
elif [[ ${@} =~ ".*HD.avi.*" ]]; then
	cutwith=smartmkvmerge
elif [[ ${@} =~ ".*mp4.*" ]]; then
	cutwith=smartmkvmerge
else
	cutwith=smartmkvmergeavconv
fi

outputdir="$(pwd)"
while [ "$1" != "${1#-}" ] ; do	# solange der naechste parameter mit "-" anfaengt...
	case ${1#-} in
	x) cutwith="avidemux";;
	n) cutwith="dontcut"; check=0;;
	s) cutwith="avisplit";;
	sm) cutwith="smartmkvmerge";;
	sma) cutwith="smartmkvmergeavconv";;
	l) local=1;;
	nl) local=0;;
	d) download=1;;
	o) outputdir="$2";shift;;
	nd) download=0;;
	c) check=1;;
	nc) check=0;;
	i) automode=0;;
	a) automode=1;;
	m) min_rating=$2; shift;;
	*) help; exit 0;;
	esac
	shift
done


# benoetigte ordner (falls nicht vorhanden) erstellen
workdir="$(pwd)"

if [ ! -d "$tempdir" ] ; then
	mkdir $tempdir
	chmod 777 $tempdir
	if [ ! -d "$tempdir" ] ; then
		echo -e "$c_error Temporaerer Ordner $tempdir nicht gefunden!$c_end" >&2
		exit 3
	fi
fi
if [ $# -ne 0 ]; then
	tmp=$(find $tempdir -name "`basename $1`*" | tail -n 1)
	if [ $? -eq 0 -a -n "$tmp" ]; then
		tempdir=$(dirname $tmp)
	else
		tempdir="$tempdir/$$"
		mkdir -p "$tempdir"
	fi
else
	echo "Aufruf: $0 <Optionen> <Film>"
	exit 2
fi

tempdir=${tempdir%/}
if [[ "${outputdir:0:1}" != "/" ]]
then
	outputdir=${workdir}/${outputdir}
fi
cutdir="${outputdir}"
if [ ! -d "${outputdir}" ] ; then
	mkdir -p "${outputdir}"
fi

# zu schneidende dateien durchgehen...
file=$@
cd "${workdir}"
if [[ ${file:0:1} != "/" ]]
then
	file=`cd "${file%/*}" 2>/dev/null ; pwd`/"${file##*/}"	# absoluten dateinamen ermitteln
fi

# lokale cutlists kopieren (passende wird nach inhalt ausgewaehlt)
[ $local -ne 0 ] && cp *.cutlist $tempdir 2>/dev/null

cd "${outputdir}"

[ $download -ne 0 ] && dlCutlists "$file"
findBestCutlist "$file"
usecl=$?	# zurueckgegebene cutlist verwenden. (array-index)
(( $usecl == 0 )) && 
{
	rm -rf $tempdir
	exit 10
	# abbruch, film nicht schneiden
}
#  usecl=$((usecl-1))
if [ -n "${url[$usecl]}" ] ; then
	dlCutlist $usecl
fi
format_string=$( [ ${vcf2format[$usecl]} -eq 1 ] && echo "VCF2Cutlist-Standard" || echo "Assistant-Standard" )
printf "\nSchneide Film $c_filename%s$c_end mit folgender Cutlist:\n\n%s von $c_author %s $c_end\nAutor-Wertung: $c_rating %d $c_end\t\tUser-Wertung: $c_rating %s $c_end (%d Stimmen)\nFormat: %s\tAnzahl Schnitte: $c_cuts %d $c_end\nKommentar: %s\n" ${file##*/} "${cutlist[$usecl]}" "${author[$usecl]}" "${rating[$usecl]}" "${userrating[$usecl]%|*}" "${userrating[$usecl]#*|}" "$format_string" "${cuts[$usecl]}" "${comment[$usecl]}"
echo URL: ${url[$usecl]}
if [ -n "${error[$usecl]}" ] ; then
	echo -e "$c_error${error[$usecl]}$c_end" >&2
fi
if [ -n "${content[$usecl]}" ] ; then
	echo -e "${content[$usecl]}"
fi
if [ -n "${errordesc[$usecl]}" ] ; then
	echo -e "${errordesc[$usecl]}"
fi
cutfilm "$file" "${cutlist[$usecl]}" "${vcf2format[$usecl]}"

# temporaeren ordner loeschen
cleanup 0

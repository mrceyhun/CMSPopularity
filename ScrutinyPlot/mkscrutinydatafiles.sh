#!/bin/bash

# Required arguments
# $1 -- Name of Phedex CSV file with these fields
# site,dataset,rdate,gid,min_date,max_date,ave_size,max_size,days
# $2 -- Name of DBS CSV files with these fields:
# dataset,size,nfiles,nevents
# $3 -- Directory containing dataset*.csv files with these fields
# dataset,user,ExitCode,Type,TaskType,rec_time,sum_evts,sum_chr,date,rate,tier

begindtrng=20170101
enddtrng=20171231
middt=20170701
lastfracdt=20171001

wkdir=/tmp/$USER/popularity
mkdir -p $wkdir

# 1. Get datasets and their sizes
# Fields 2, 7, 3, and 6 are dataset name, average size, replica date and end date of its presence
awk -F , '{print $2 "," $7 "," $3 "," $6}' "$1" | grep -v 'dataset,ave' | sort -t , -k 1,1 -k 3,3 -k 4,4 > $wkdir/dsandsz$$.txt
awk -F , -f findDSlifetime.awk $wkdir/dsandsz$$.txt > $wkdir/dsSzLif$$.txt
awk -F , '{print $1 "," $4}' $2 | sed 's/"//g' | sort -t , -k1,1 > $wkdir/dsEvts$$.txt
# dsEvts has dataset and number of events
join -t , -j 1 $wkdir/dsSzLif$$.txt $wkdir/dsEvts$$.txt > $wkdir/dsSzDur$$.txt
# dsSzDur has dataset, size, begin date, end date, and number of events

# 2. Get daily accesses for each dataset
for jobdtfile in "$3"/dataset*.csv ; do
	# Fields 1 and 7 are dataset name and kilo events used. Access date is not reliable -- use file name
	accdate=`echo $jobdtfile | sed 's/.*-\(.*\)\..*/\1/'`
	grep -v 'dataset,user,ExitCode,' $jobdtfile | awk -F , -v accdate=$accdate '{if ($7 != "null" && $7 > 0) {print $1 "," accdate "," $7 * 1000}}' | grep -v 'null' | sort -t , -k1,1 >> $wkdir/dsuses$$.txt
done

# 3. Add up uses/day for each DS
awk -F , -f sumDailyUses.awk $wkdir/dsuses$$.txt |  sort -t , -k1,1 -k2,2 > $wkdir/sumdsuses$$.txt
# sumdsuses$$.txt fields are dataset name, access date, number of accesses, and number of events used for that date

# 4. Join uses and sizes
join -t , -j 1 $wkdir/dsSzDur$$.txt $wkdir/sumdsuses$$.txt > $wkdir/sumusesz$$.txt
# sumusesz$$.txt fields are dataset name, size, begin date, end date, dataset events, access date, number of accesses, and number of events for that date

awk -F , '{if ($5 > 0) {print $1 "," $7 "," $2 * $8/$5 "," $6}}' $wkdir/sumusesz$$.txt > $wkdir/sumEvtsusesz$$.txt
# sumEvtsusesz$$.txt fields are dataset name, number of accesses, number of bytes read, access date

# 5. Create two subset files by date
# Field 4 is the access date
awk -F , -v dtboundary=$lastfracdt '{if ($4 >= dtboundary) {print $0}}' $wkdir/sumEvtsusesz$$.txt  > $wkdir/dayuses3month$$.txt
awk -F , -v dtboundary=$middt '{if ($4 >= dtboundary) {print $0}}' $wkdir/sumEvtsusesz$$.txt  > $wkdir/dayuses6month$$.txt
# Uses files fields are dataset name, number of accesses, number of bytes read, access date

# 6. Sum up all daily uses for each dataset
awk -F , -f sumAllUses.awk $wkdir/sumEvtsusesz$$.txt > $wkdir/usesfullperiod$$.txt
awk -F , -f sumAllUses.awk $wkdir/dayuses6month$$.txt > $wkdir/uses6month$$.txt
awk -F , -f sumAllUses.awk $wkdir/dayuses3month$$.txt > $wkdir/uses3months$$.txt
# Fields are dataset name, number of accesses for period, number of bytes for period


# 6. Get list of unused datasets
# 7. Get the total size of unused datasets
function getUnused {  # $1 is earliest date for dataset, $2 is uses file for period
	join -t , -j 1 -v 1 $wkdir/dsSzDur$$.txt $2 > $wkdir/unusedDS$1$$.txt
	# unusedDS$$.txt fields are dataset name, size, begin date, end date of last presence

	unusedtotnow=`awk -F , -v begindate=$1 -v enddate=$enddtrng '{ if ($3 >= begindate && $3 <= enddate) {sum = sum + $2}} END{print sum}' $wkdir/unusedDS$1$$.txt`
	unusedtotold=`awk -F , -v begindate=$1 '{ if ($3 < begindate && $4 >= begindate) {sum = sum + $2}} END{print sum}' $wkdir/unusedDS$1$$.txt`
	[ -z "$unusedtotnow" ] && unusedtotnow=0
	[ -z "$unusedtotold" ] && unusedtotold=0
	echo Unused total `expr $unusedtotnow / 1024 / 1024 / 1024` GB
	echo Unused total `expr $unusedtotold / 1024 / 1024 / 1024` GB

	# 8. Add entry for unused datasets to uses file
	echo "not_used,0,$unusedtotnow" >> $2
	echo "not_used,-1,$unusedtotold" >> $2
}

getUnused $lastfracdt $wkdir/uses3months$$.txt
getUnused $middt $wkdir/uses6month$$.txt
getUnused $begindtrng $wkdir/usesfullperiod$$.txt
#!/bin/bash
set -e

show_help() {
  cat <<EOF
Usage: $0 [-o BACKUP_NAME]
  [-a] [-n] [-v] [-s] [-u] [-c] [-t] [-h]

Create backups, selecting files and directories.

Description:
	This tool shows a list of files in the current directory.
	Items can be selected for inclusion in the backup using checkboxes.
	Chosen files are then copied, moved, and archived in the backup.
	These files are stored as preferences for new backups in the
	same directory.

Dependencies:
	This script uses notify-send (see libnotify or libnotify-bin)
	as well as zenity.

Options:
   -o   Specify the backup name (suffix .tar.gz will be added).
   -a   Show hidden directories and files.
   -v   Enable verbose mode for detailed output.
   -s   Sort items by size (instead of name) before displaying.
   -u   Uncheck all files and directories by default (overrides preferences).
   -c   Check all files and directories by default (overrides preferences).
   -t   Change minimum duration for sending a notification (default: 10s).
   -h   Show this text.

Example:
	$0 -o mybackup -a -v
	# backup will be the file mybackup.tar.gz
EOF
}

backup_folder=$(date +"backup_%Hh%Mm%Ss_%d-%h-%y")
backup_file=$backup_folder.tar.gz

save_preferences=true
hidden_files=false
verbose=false
sorted=false
notify_min_time=10

uncheck_all=false
check_all=false

while getopts "o:avsucht:" o; do
	case "${o}" in
	o)
		backup_folder=${OPTARG}
		backup_file=$backup_folder.tar.gz
		if [[ -e $backup_folder ]]; then
			echo "Output folder already exists." >&2
			exit 1
		fi
		;;
	a)
		hidden_files=true
		;;
	v)
		verbose=true
		;;
	s)
		sorted=true
		;;
	u)
		uncheck_all=true
		;;
	c)
		check_all=true
		;;
	h)
		show_help
		exit
		;;
	t)
		notify_min_time=${OPTARG}
		;;
	*)
		echo "Unknown argument ${OPTARG}" >&2
		show_help
		exit 1
		;;
	esac
done

has_preferences=false
if [ -f .backup_pref ]; then
	echo "Found preferences file."
	has_preferences=true
fi

if $verbose; then
	echo "Listing files in $PWD..."
fi

files=`/usr/bin/du -ahd1 | head -n -1`
if ! $hidden_files; then
	files=`echo "$files" | grep -v '\\./\\.'`
fi

if $sorted; then
	files=$(echo "$files" | sort -hr)
fi

files=`echo "$files" | cut -f2`

if $verbose; then
	echo "Parsing data to build a zenity dialog..."
fi

list=""
for file in $files; do
	if $check_all; then
		list+="True "
	elif $uncheck_all; then
		list+="False "
	elif $has_preferences; then
		if grep -Fwq "$file" .backup_pref; then
			list+="True "
		else
			list+="False "
		fi
	else
		if [[ $file = ./.* ]]; then
			list+="False "
		else
			list+="True "
		fi
	fi
	list+="$file  "
	list+="$(du -hs $file | cut -f1) "
	list+="$(date +%x -r $file) "
done

if $verbose; then
	echo "Creating and opening zenity dialog..."
fi

result=`zenity --width=500 --height=600 \
	--list --checklist \
	--title "Backup dialog" --text "Select files for backup in <b>$backup_file</b>:" \
	--column "" --column "Fichiers" --column "File size" --column "Last edited" \
	$list || true`

start=`date +%s`

if [ -z $result ]; then
	echo "Cancelled backup creation."
	exit 0
fi

selected=`echo $result | sed 's@|@ @g'`

if $save_preferences; then
	if $verbose; then
		echo "Writing preferences in ./.backup_pref..."
	fi
	echo $selected > .backup_pref
fi

if $verbose; then
	echo "Copying data to backup folder..."
fi

mkdir $backup_folder
for file in $selected; do
	/usr/bin/cp -r $file $backup_folder
done

echo "Creating archive..."

tar -cvzf $backup_file $backup_folder 1> /dev/null
rm -rf $backup_folder

end=`date +%s`

runtime=$(($end - $start))

echo "Backup done in $runtime second(s)."

if [ $runtime -gt $notify_min_time ]; then
	notify-send -u normal "Backup successfully created"
fi

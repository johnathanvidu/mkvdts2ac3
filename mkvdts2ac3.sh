#!/bin/bash
# mkvdts2ac3.sh - add an AC3 track to an MKV from its DTS track
# Author: Jake Wharton <jakewharton@gmail.com>
# Website: http://jakewharton.com
#          http://github.com/JakeWharton/mkvdts2ac3/
# Version: 1.0.6
# License:
#   Copyright 2009 Jake Wharton
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

displayhelp() {
	echo "Usage: $0 [options] <filename>"
	echo "Options:"
	echo "     -c TITLE,        Custom AC3 track title."
	echo "     --custom TITLE"
	echo "     -d, --default    Mark AC3 track as default."
	echo "     -e, --external   Leave AC3 track out of file. Does not modify the"
	echo "                      original matroska file. This overrides '-n' and"
	echo "                      '-d' arguments."
	echo "     -f, --force      Force AC3 creation even if one already exists."
	echo "     -k, --keep-dts   Keep external DTS track (implies '-n')."
	echo "     -n, --no-dts     Do not retain the DTS track."
	echo "     -o MODE          Pass a custom audio output mode to libdca."
	echo "     -p PRIORITY      Modify niceness of executed commands."
	echo "     -t TRACKID,"
	echo "     --track TRACKID  Specify alternate DTS track."
	echo "     -w FOLDER,"
	echo "     --wd FOLDER      Specify alternate temporary working directory."
	echo ""
	echo "     --test           Print commands only, execute nothing."
	echo "     --debug          Print commands and pause before executing each."
	echo ""
	echo "     -h, --help       Print command usage."
	echo "     -v, --version    Print script version information."
}



# Used to time execution
START=$(date +%s)

# Display version header
echo "mkvdts2ac3-1.0.6 - by Jake Wharton <jakewharton@gmail.com>"
echo ""

# Debugging flags
# DO NOT EDIT THESE! USE --debug OR --test ARGUMENT INSTEAD.
PRINT=0
PAUSE=0
EXECUTE=1

dopause() {
	if [ $PAUSE = 1 ]; then
		read
	fi
}

# Default values
PRIORITY=0



# Parse arguments and/or filename
while [ -z "$MKVFILE" ]; do

	# If we're out of arguments no filename was passed
	if [ $# -eq 0 ]; then
		echo "ERROR: You must supply a filename."
		echo ""
		displayhelp
		exit 1
	fi

	case "$1" in

		"-c" | "--custom" )
			# Use custom name for AC3 track
			shift
			DTSNAME=$1
		;;
		"-d" | "--default" )
			# Only allow this if we aren't making the file external
			if [ -z $EXTERNAL ]; then
				DEFAULT=1
			fi
		;;
		"-e" | "--external" )
			EXTERNAL=1
			# Don't allow -d or -n switches if they're already set
			NODTS=0
			KEEPDTS=0
			DEFAULT=0
		;;
		"-f" | "--force" )
			FORCE=1
		;;
		"-k" | "--keep-dts" )
			# Only allow external DTS track if muxing AC3 track
			if [ -z $EXTERNAL ]; then
				KEEPDTS=1
			fi

		;;
		"-n" | "--no-dts" )
			# Only allow this if we aren't making the file external
			if [ -z $EXTERNAL ]; then
				NODTS=1
			fi
		;;
		"-o" )
			# Move required audio mode value "up"
			shift
			AUDIOMODE=$1
		;;
		"-p" )
			# Move required priority value "up"
			shift
			PRIORITY=$1
		;;
		"-t" | "--track" )
			# Move required TRACKID argument "up"
			shift
			DTSTRACK=$1
		;;
		"-w" | "--wd" )
			# Specify working directory manually
			shift
			WD=$1
		;;


		"--test" )
			# Echo commands and do not execute
			if [ $PAUSE = 1 ]; then
				echo "WARNING: --test overrides previous --debug flag."
			fi

			PRINT=1
			EXECUTE=0
		;;
		"--debug" )
			# Echo commands and pause before executing
			if [ $EXECUTE = 0 ]; then
				echo "ERROR: --debug flag not valid with --test."
				displayhelp
				exit 1
			fi

			PRINT=1
			PAUSE=1
			EXECUTE=1
		;;



		"-h" | "--help" )
			displayhelp
			exit 0
		;;
		"-v" | "--version" )
			# Version information is always displayed so just exit here
			exit 0
		;;


		-* | --* )
			echo "ERROR: Invalid argument '$1'."
			echo ""
			displayhelp
			exit 1
		;;

		* )
			MKVFILE=$1
			shift

			# Ensure there are no arguments after the filename
			if [ $# -ne 0 ]; then
				echo "ERROR: You cannot supply any arguments after the filename. Please check the command syntax below against what has been parsed."
				echo ""
				echo "Control Flags:"
				echo "  Strip DTS: $NODTS"
				echo "  Keep DTS: $KEEPDTS"
				echo "  Set AC3 default: $DEFAULT"
				echo "  External AC3: $EXTERNAL"
				echo "  DTS track: $DTSTRACK"
				echo "  MKV file: $MKVFILE"
				echo ""
				echo "Debugging Flags:"
				echo "  Print commands: $PRINT"
				echo "  Pause after print: $PAUSE"
				echo "  Execute commands: $EXECUTE"
				echo ""
				displayhelp
				exit 1
			fi
		;;
	esac

	# Move arguments "up" one spot
	shift
done



# File and dependency checks
if [ $EXECUTE = 1 ]; then
	# Check the file exists and we have permissions
	if [ ! -f "$MKVFILE" ]; then
		echo "ERROR: '$MKVFILE' is not a file."
		exit 1
	elif [ ! -r "$MKVFILE" ]; then
		echo "ERROR: Cannot read '$MKVFILE'."
		exit 1
	elif [ -z $EXTERNAL ]; then
		if [ ! -w "$MKVFILE" ]; then
			# Only check write permission if we're not keeping the AC3 external
			echo "ERROR: Cannot write '$MKVFILE'."
			exit 1
		fi
	fi

	# Check dependencies (mkvtoolnix, libdca, aften)
	if [ -z "$(which mkvmerge)" -o ! -x "$(which mkvmerge)" ]; then
		echo "ERROR: The program 'mkvmerge' is not in the path. Is mkvtoolnix installed?"
		exit 1
	elif [ -z "$(which mkvextract)" -o ! -x "$(which mkvextract)" ]; then
		echo "ERROR: The program 'mkvextract' is not in the path. Is mkvtoolnix installed?"
		exit 1
	elif [ -z "$(which mkvinfo)" -o ! -x "$(which mkvinfo)" ]; then
		echo "ERROR: The program 'mkvinfo' is not in the path. Is mkvtoolnix installed?"
		exit 1
	elif [ -z "$(which dcadec)" -o ! -x "$(which dcadec)" ]; then
		echo "ERROR: The program 'dcadec' is not in the path. Is libdca installed?"
		exit 1
	elif [ -z "$(which aften)" -o ! -x "$(which aften)" ]; then
		echo "ERROR: The program 'aften' is not in the path. Is aften installed?"
		exit 1
	fi
fi

if [ "$(mkvmerge -i "$MKVFILE" | grep -i "A_AC3")" ]; then
	if [ $FORCE = 1 ]; then
		echo "WARNING: AC3 track(s) already exist in $MKVFILE. Ignoring..."
	else
		echo "ERROR: AC3 track(s) already exist in $MKVFILE. Exiting."
		exit 1
	fi
fi

# Path to file
DEST=$(dirname "$MKVFILE")

# File name without the extension
NAME=$(basename "$MKVFILE" .mkv)

# Working Directory
# I personally use the current directory since my temp partition
# is tiny (WD="."). To use the directory the file is in use $DEST.
if [ -z $WD ]; then
	WD="/tmp"
fi

# Setup temporary files
DTSFILE="$WD/$NAME.dts"
AC3FILE="$WD/$NAME.ac3"
TCFILE="$WD/$NAME.tc"
NEWFILE="$WD/$NAME.new.mkv"

if [ $PRINT = 1 ]; then
	echo "MKV FILE: $MKVFILE"
	echo "DTS FILE: $DTSFILE"
	echo "AC3 FILE: $AC3FILE"
	echo "TIMECODE: $TCFILE"
	echo "NEW FILE: $NEWFILE"
	echo "WORK DIR: $WD"
fi



# If the track id wasn't specified via command line then search for the first DTS audio track
if [ -z $DTSTRACK ]; then
	if [ $PRINT = 1 ]; then
		echo ""
		echo "Find first DTS track in MKV file."
		echo "> mkvmerge -i \"$MKVFILE\" | grep -m 1 \"audio (A_DTS)\" | cut -d ":" -f 1 | cut -d \" \" -f 3"
		DTSTRACK="DTSTRACK"
		dopause
	fi
	if [ $EXECUTE = 1 ]; then
		DTSTRACK=$(mkvmerge -i "$MKVFILE" | grep -m 1 "audio (A_DTS)" | cut -d ":" -f 1 | cut -d " " -f 3)

		# Check to make sure there is a DTS track in the MVK
		if [ -z $DTSTRACK ]; then
			echo "ERROR: There are no DTS tracks in '$MKVFILE'."
			exit 1
		fi
	fi
else
	# Checks to make sure the command line argument track id is valid
	if [ $PRINT = 1 ]; then
		echo ""
		echo "Checking to see if DTS track specified via arguments is valid."
		echo "> mkvmerge -i \"$MKVFILE\" | grep \"Track ID $DTSTRACK: audio (A_DTS)\""
		dopause
	fi
	if [ $EXECUTE = 1 ]; then
		VALID=$(mkvmerge -i "$MKVFILE" | grep "Track ID $DTSTRACK: audio (A_DTS)")

		if [ -z "$VALID" ]; then
			echo "ERROR: Track ID '$DTSTRACK' is not a DTS track and/or does not exist."
			exit 1
		else
			echo "INFO: Using alternate DTS track with ID '$DTSTRACK'."
		fi
	fi
fi



# Get the specified DTS track's information
if [ $PRINT = 1 ]; then
	echo ""
	echo "Extract track information for selected DTS track."
	echo "> mkvinfo \"$MKVFILE\" | grep -A 25 \"Track number: $DTSTRACK\""
	INFO="INFO"
	dopause
fi
if [ $EXECUTE = 1 ]; then
	INFO=$(mkvinfo "$MKVFILE" | grep -A 25 "Track number: $DTSTRACK")
fi

#Get the language for the DTS track specified
if [ $PRINT = 1 ]; then
	echo ""
	echo "Extract language from track info."
	echo "> echo \"$INFO\" | grep -m 1 \"Language\" | cut -d \" \" -f 5"
	DTSLANG="DTSLANG"
	dopause
fi
if [ $EXECUTE = 1 ]; then
	DTSLANG=$(echo "$INFO" | grep -m 1 "Language" | cut -d " " -f 5)
fi

# Check if a custom name was already specified
if [ -z $DTSNAME ]; then
	# Get the name for the DTS track specified
	if [ $PRINT = 1 ]; then
		echo ""
		echo "Extract name for selected DTS track. Change DTS to AC3 and update bitrate if present."
		echo "> echo \"$INFO\" | grep -m 1 \"Name\" | cut -d \" \" -f 5- | sed \"s/DTS/AC3/\" | awk '{gsub(/[0-9]+(\.[0-9]+)?(M|K)bps/,\"448Kbps\")}1'"
		DTSNAME="DTSNAME"
		dopause
	fi
	if [ $EXECUTE = 1 ]; then
		DTSNAME=$(echo "$INFO" | grep -m 1 "Name" | cut -d " " -f 5- | sed "s/DTS/AC3/" | awk '{gsub(/[0-9]+(\.[0-9]+)?(M|K)bps/,"448Kbps")}1'
	fi
fi

# Extract timecode information for the target track
if [ $PRINT = 1 ]; then
	echo ""
	echo "Extract timecode information for the audio track."
	echo "> mkvextract timecodes_v2 \"$MKVFILE\" $DTSTRACK:\"$TCFILE\""
	echo "> sed -n \"2p\" \"$TCFILE\""
	echo "> rm -f \"$TCFILE\""
	DELAY="DELAY"
	dopause
fi
if [ $EXECUTE = 1 ]; then
	nice -n $PRIORITY mkvextract timecodes_v2 "$MKVFILE" $DTSTRACK:"$TCFILE"
	DELAY=$(sed -n "2p" "$TCFILE")
	rm -f "$TCFILE"
fi



# Extract the DTS track
if [ $PRINT = 1 ]; then
	echo ""
	echo "Extract DTS file from MKV."
	echo "> mkvextract tracks \"$MKVFILE\" $DTSTRACK:\"$DTSFILE\""
	dopause
fi
if [ $EXECUTE = 1 ]; then
	nice -n $PRIORITY mkvextract tracks "$MKVFILE" $DTSTRACK:"$DTSFILE"

	# Check to make sure the extraction completed successfully
	if [ $? -ne 0 ]; then
		echo "ERROR: Extracting the DTS track failed."
		exit 1
	fi
fi

# Convert DTS to AC3
if [ $PRINT = 1 ]; then
	echo ""
	echo "Converting DTS to AC3."
	echo "> dcadec -o $AUDIOMODE \"$DTSFILE\" | aften -v 0 - \"$AC3FILE\""
	dopause
fi
if [ $EXECUTE = 1 ]; then
	if [ -z $AUDIOMODE ]; then
		AUDIOMODE="wavall"
	fi

	nice -n $PRIORITY dcadec -o $AUDIOMODE "$DTSFILE" | nice -n $PRIORITY aften -v 0 - "$AC3FILE"

	# Check to make sure the conversion completed successfully
	if [ $? -ne 0 ]; then
		echo "ERROR: Converting the DTS to AC3 failed."

		rm -f "$DTSFILE" #clean up
		rm -f "$AC3FILE" #clean up
		exit 1
	fi
fi

# Remove DTS file unless explicitly keeping DTS track
if [ -z $KEEPDTS ]; then
	if [ $PRINT = 1 ]; then
		echo ""
		echo "Removing temporary DTS file."
		echo "> rm -f \"$DTSFILE\""
		dopause
	fi
	if [ $EXECUTE = 1 ]; then
		rm -f "$DTSFILE"

		if [ $? -ne 0 ]; then
			echo "WARNING: Could not delete temporary file '$DTSFILE'. Please do this manually after the script has completed."
		fi
	fi
fi



# Check there is enough free space for AC3+MKV
if [ $EXECUTE = 1 ]; then
	MKVFILESIZE=$(\stat -c %s "$MKVFILE")
	AC3FILESIZE=$(\stat -c %s "$AC3FILE")
	WDFREESPACE=$(\df "$WD" | tail -1 | awk '{print $4}')
	if [ $(($MKVFILESIZE + $AC3FILESIZE)) -gt $WDFREESPACE ]; then
		echo "ERROR: There is not enough free space on '$WD' to create the new file."

		rm -f "$AC3FILE" #clean up
		exit 1
	fi
fi

if [ $EXTERNAL ]; then
	# We need to trick the rest of the script so that there isn't a lot of
	# code duplication. Basically $NEWFILE will be the AC3 track and we'll
	# change $MKVFILE to where we want the AC3 track to be so we don't
	# overwrite the MKV file only an AC3 track
	NEWFILE=$AC3FILE
	MKVFILE="$DEST/$NAME.ac3"
else
	# Start to "build" command
	CMD="nice -n $PRIORITY mkvmerge -o \"$NEWFILE\""

	# If user doesn't want the original DTS track drop it
	if [ $NODTS ]; then
		# Count the number of audio tracks in the file
		AUDIOTRACKS=$(mkvmerge -i "$MKVFILE" | grep "audio (A_" | wc -l) #)#<-PN2 highlighting fix

		if [ $AUDIOTRACKS -eq 1 ]; then
			# If there is only the DTS audio track then drop all audio tracks
			CMD="$CMD -A"
		else
			# Get a list of all the other audio tracks
			SAVETRACKS=$(mkvmerge -i "$MKVFILE" | grep "audio (A_" | cut -d ":" -f 1 | grep -vx "Track ID $DTSTRACK" | cut -d " " -f 3 | awk '{ if (T == "") T=$1; else T=T","$1 } END { print T }')
			# And copy only those
			CMD="$CMD -a \"$SAVETRACKS\""
		fi
	fi

	# Add original MKV file to command
	CMD="$CMD \"$MKVFILE\""

	# If user wants new AC3 as default then add appropriate arguments to command
	if [ $DEFAULT ]; then
		CMD="$CMD --default-track 0"
	fi

	# If the language was set for the original DTS track set it for the AC3
	if [ $DTSLANG ]; then
		CMD="$CMD --language 0:$DTSLANG"
	fi

	# If the name was set for the original DTS track set it for the AC3
	if [ "$DTSNAME" ]; then
		CMD="$CMD --track-name 0:\"$DTSNAME\""
	fi

	# If there was a delay on the original DTS set the delay for the new AC3
	if [ $DELAY != 0 ]; then
		CMD="$CMD --sync 0:$DELAY"
	fi

	# Append new AC3
	CMD="$CMD \"$AC3FILE\""

	# Run it!
	if [ $PRINT = 1 ]; then
		echo ""
		echo "Running main remux."
		echo "> $CMD"
		dopause
	fi
	if [ $EXECUTE = 1 ]; then
		eval $CMD

		if [ $? -ne 0 ]; then
			echo "ERROR: Merging the AC3 track back into the MKV failed."

			rm -f "$AC3FILE" #clean up
			rm -f "$NEWFILE" #clean up
			exit 1
		fi
	fi

	# Delete AC3 file
	if [ $PRINT = 1 ]; then
		echo ""
		echo "Removing temporary AC3 file."
		echo "> rm -f \"$AC3FILE\""
		dopause
	fi
	if [ $EXECUTE = 1 ]; then
		rm -f "$AC3FILE"

		if [ $? -ne 0 -a $EXECUTE = 0 ]; then
			echo "WARNING: Could not delete temporary file '$AC3FILE'. Please do this manually after the script has completed."
		fi
	fi
fi



# Check to see if the two files are on the same device
NEWFILEDEVICE=$(\df "$WD" | tail -1 | cut -d " " -f 1)
DSTFILEDEVICE=$(\df "$DEST" | tail -1 | cut -d " " -f 1)

if [ $EXECUTE = 1 ]; then
	echo "Copying new file over old file. DO NOT POWER OFF OR KILL THIS PROCESS OR YOU WILL EXPERIENCE DATA LOSS!"
fi

if [ "$NEWFILEDEVICE" = "$DSTFILEDEVICE" ]; then
	# If we're working on the same device just move the file over the old one
	if [ $PRINT = 1 ]; then
		echo ""
		echo "Moving old file over new one."
		echo "> mv \"$NEWFILE\" \"$MKVFILE\""
		dopause
	fi
	if [ $EXECUTE = 1 ]; then
		mv "$NEWFILE" "$MKVFILE"

		#TODO: add move exit code check
	fi
else
	# Check there is enough free space for the new file
	if [ $EXECUTE = 1 ]; then
		MKVFILEDIFF=$(($(\stat -c %s "$NEWFILE") - $MKVFILESIZE))
		DESTFREESPACE=$(\df -P "$DEST" | tail -1 | awk '{print $4}')

		if [ $MKVFILEDIFF -gt $DESTFREESPACE ]; then
			echo "ERROR: There is not enough free space to copy the new MKV over the old one. Free up some space and then copy '$NEWFILE' over '$MKVFILE'."
			exit 1
		fi
	fi

	# Copy our new MKV with the AC3 over the old one OR if we're using the -e
	# switch then this actually copies the AC3 file to the original directory
	if [ $PRINT = 1 ]; then
		echo ""
		echo "Copying new file over the old one."
		echo "> cp \"$NEWFILE\" \"$MKVFILE\""
		dopause
	fi
	if [ $EXECUTE = 1 ]; then
		cp "$NEWFILE" "$MKVFILE"

		# Check file sizes are equal to ensure the full file was copied
		OLDFILESIZE=$(\stat -c %s "$NEWFILE")
		NEWFILESIZE=$(\stat -c %s "$MKVFILE")

		if [ $? -ne 0 -o $OLDFILESIZE -ne $NEWFILESIZE ]; then
			echo "ERROR: There was an error copying the new MKV over the old one. You can perform this manually by copying '$NEWFILE' over '$MKVFILE'."
			exit 1
		fi
	fi

	# Remove new file in $WD
	if [ $PRINT = 1 ]; then
		echo ""
		echo "Remove working file."
		echo "> rm -f \"$NEWFILE\""
		dopause
	fi
	if [ $EXECUTE = 1 ]; then
		rm -f "$NEWFILE"

		if [ $? -ne 0 -a $EXECUTE = 0 ]; then
			echo "WARNING: Could not delete temporary file '$NEWFILE'. Please do this manually after the script has completed."
		fi
	fi
fi



# Display total execution time
END=$(date +%s)
if [ $EXECUTE = 1 -a $PAUSE = 0 ]; then
	echo "Total processing time: $(($END - $START)) seconds."
fi

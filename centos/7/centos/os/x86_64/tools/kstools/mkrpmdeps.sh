#/bin/sh
blankline="                             "

function clean_repo()
{
	ARCH="`basename $BOOTCD_PATH`"
	rm -rf /var/lib/yum/repos/$ARCH/?/tmp
	rm -rf /var/cache/yum/$ARCH/?/tmp
}

function rpm_resolver()
{
	## $1 is the list of RPMs to compute
	local RPM_RESOLV=$1
	## $2 is the target file output
	local resultfile=$2
	local OUTPUT=""
	if [ -f $resultfile ]; then
		OUTPUT="`cat $resultfile`\n"
	fi
	NB=0
	while [ "$RPM_RESOLV" ]; do
		if [ "$RPM_RESOLV" == "^$" ]; then
			break
		fi
		RPM=$(echo -e "$RPM_RESOLV" | head -n1)
		local TMP1=$RPM_RESOLV
		RPM_RESOLV=$(echo -e "$TMP1" | sed -e "/^$RPM$/d")
		if [ "$RPM" ]; then
			local STRIPED=$(echo "$RPM" | sed -e "s/.*://")
			local TESTRPM=$(echo -e "$OUTPUT" | grep "^$STRIPED$")
			if [ -z "$TESTRPM" ]; then
				# Test if there are unresolved dependencies for this package
				if [ -f $BOOTCD_PATH/tools/profiles/$PROFILE/unresolved ]; then
					UNRESOLVED=$(cat $BOOTCD_PATH/tools/profiles/$PROFILE/unresolved | grep "package: $STRIPED from")
					if [ -z "$UNRESOLVED" ]; then
						UNRESOLVED=$(cat $BOOTCD_PATH/tools/profiles/$PROFILE/unresolved | grep "package:.*:$STRIPED from")
					fi
				else
					UNRESOLVED=""
				fi
				if [ "$UNRESOLVED" ]; then
					UNRES_RPM=""
					UNRESLOVED_DEPS=""
					while read line; do
						if [ -z "$UNRES_RPM" ]; then
							UNRES_RPM=$(echo $line | grep "package: $STRIPED from")
							if [ -z "$UNRES_RPM" ]; then
								UNRES_RPM=$(echo $line | grep "package:.*:$STRIPED from")
							fi
							END=""
						else
							END=$(echo $line | grep "^package: ")
							if [ -z "$END" ]; then
								UNRESLOVED_DEPS="$UNRESLOVED_DEPS\n▸\t$line"
							else
								break
							fi
						fi
					done < $BOOTCD_PATH/tools/profiles/$PROFILE/unresolved
					echo "" 1>&2
					echo "Package $STRIPED has missing dependencies:" 1>&2
					echo -e "$UNRESLOVED_DEPS"
					if [ "$FORCE" == false ]; then
						echo "returning !"
						return 1
					fi
				fi
				
				NB=$(( NB + 1 ))
				OUTPUT="$OUTPUT$STRIPED\n"
				echo -ne "\r[$NB] Added $RPM $blankline"
				ARCHOPT=''
				# If RPM is not 32bits then only query deps on noarch and x86_64
				if [ "$ARCH" == "x86_64" ]; then
					I32="`echo $RPM | sed -e "s/.*\.//" | grep "i.86"`"
					if [ -z "$I32" ]; then
						ARCHOPT="--arch=x86_64,noarch "
					fi
				fi
				local TMPLIST=$(repoquery --repofrompath=tmp,file:$BOOTCD_PATH/ \
				                          --envra \
				                          --repoid=tmp $ARCHOPT\
				                          --requires \
				                          --resolve $RPM 2>/tmp/rpms_unresolved.err)
				ERR=$(cat /tmp/rpms_unresolved.err | grep -v "Repository .* is listed more than once")
				if [ "$ERR" ]; then
					echo "" 1>&2
					echo "Package $STRIPED has missing dependencies:" 1>&2
					echo "$ERR" 1>&2
					if [ "$FORCE" == false ]; then
						return 1
					fi
				fi
				if [ -z "$TMPLIST" ]; then
					echo "" 1>&2
					echo "ERROR: Package $RPM_VERS is missing !" 1>&2
					if [ "$FORCE" == false ]; then
						return 1
					fi
				fi
				for entry in $TMPLIST; do
					local toadd=$(echo $entry | sed -e "s/.*://")
					local TEST1=$(echo -e "$OUTPUT" | grep "^$toadd$")
					local TEST2=$(echo -e "$RPM_RESOLV" | grep "^$toadd$")
					if [ -z "$TEST1" -a -z "$TEST2" ]; then
						RPM_RESOLV="$toadd\n$RPM_RESOLV"
					fi
				done
			fi
		fi
	done
	echo -e "$OUTPUT" | sed -e "/^$/d" > $resultfile
	#eval $__resultvar="'$OUTPUT'"
	return 0
}

function find_rpms_version()
{
	## $1 is the list of RPMs to compute
	local RPM_VERS=$1
	## $2 is the target variable to return
	local __resultvar=$2
	local OUTPUT=""
	ARCHOPT=''
	# If RPM is not 32bits then only query deps on noarch and x86_64
	if [ "$ARCH" == "x86_64" ]; then
		I32="`echo $RPM | sed -e "s/.*\.//" | grep "i.86"`"
		if [ -z "$I32" ]; then
			ARCHOPT="--arch=x86_64,noarch "
		fi
	fi
	local TMP=$(repoquery --repofrompath=tmp,file:$BOOTCD_PATH/ --envra --repoid=tmp $ARCHOPT$RPM_VERS 2>/dev/null)
	if [ "$TMP" ]; then
		for entry in $TMP; do
			toadd=$(echo $entry | sed -e "s/.*://")
			TEST1=$(echo -e "$OUTPUT" | grep "^$toadd$")
			# If the rpm is not already part of output add it
			if [ -z "$TEST1" ]; then
				OUTPUT="$OUTPUT$toadd\n"
			fi
		done
	else
		echo "" 1>&2
		echo -e "ERROR: Package $RPM_VERS is missing !" 1>&2
		if [ "$FORCE" == false ]; then
			return 1
		fi
	fi
	eval $__resultvar="'$OUTPUT'"
	return 0
}

function make_profile_list() 
{
	RPMS=$(grep -A200 "^%packages" $BOOTCD_PATH/$KS | grep -B200 "^%pre" | grep -v "^-" | grep -v "^#" | grep -v "^%packages\|^%pre\|^%include\|%end")
	INCLUDES=$(grep -A200 "^%packages" $BOOTCD_PATH/$KS | grep -B200 "^%pre" | grep -v "^-" | grep -v "^#" | grep "^%include" | sed -e "s/^%include //")
	for input in $INCLUDES; do
		INCLUDE_FILE=$(echo $input | sed -e "s|^%include ||")
		INCLUDE_RPMS=$(grep "$INCLUDE_FILE" $BOOTCD_PATH/$KS | grep -v "^%include" | sed -e "s/ *echo //" | sed -e "s/ >.*//" | sed -e "s|\"||g" | sed -e "s|\'||g" | grep -v "#")
		echo "Adding $INCLUDE_RPMS"
		RPMS="$RPMS $INCLUDE_RPMS"
	done
	ks_name=$(echo $KS | sed -e "s/ks_//" | sed -e "s/\.cfg//")
	
	GR_RESOLVED=""
	for arpm in $RPMS; do
		GR=`echo $arpm | grep "^@" | sed -e "s/@//" | sed -e "s/ /-/g" | tr '[:upper:]' '[:lower:]'`
		if [ "$GR" ]; then
			gr_name="$arpm"
			target="$BOOTCD_PATH/groups/$GR.rpms"
			if [ ! -f "$target" ]; then
				mkdir -p $BOOTCD_PATH/groups
				echo ""
				echo "Creating \"$GR\" group list ..."
				if [ ! -f "$BOOTCD_PATH/repodata/groups/$GR" ]; then
					echo "    ▸ building initial groups"
					sh $BOOTCD_PATH/tools/kstools/build_groups.sh $BOOTCD_PATH $GR
				fi
				if [ ! -f "$BOOTCD_PATH/repodata/groups/$GR" ]; then
					echo "    ▸ $GR group does not exist !"
					echo "    ▸ removing $gr_name from kickstart."
					TODEL="\\$gr_name\n"
					perl -pi -e "s/$TODEL//" $BOOTCD_PATH/$KS
				else
					GR_RPMS=`cat $BOOTCD_PATH/repodata/groups/$GR 2>/dev/null`
					echo "    ▸ checking \"$GR\" packages versions"
					find_rpms_version "$GR_RPMS" GR_VERS
					local res=$?
					if [ $res -gt 0 ]; then
						exit 1
					fi
					echo "    ▸ resolving \"$GR\" dependencies"
					rpm_resolver "$GR_VERS" "$target"
					res=$?
					if [ $res -gt 0 ]; then
						exit 1
					fi
				fi
			fi
			if [ -f "$target" ]; then
				while read line; do
					if [ "$line" ]; then
						TEST=`echo -e "$GR_RESOLVED" | grep "^$line$"`
						if [ -z "$TEST" ]; then
							GR_RESOLVED="$GR_RESOLVED$line\n"
						fi
					fi
				done < $target
			fi
		else
			find_rpms_version "$arpm" RPM_VER
			local res=$?
			if [ $res -gt 0 ]; then
				exit 1
			fi
			RPMS2CHECK="$RPMS2CHECK\n$RPM_VER"
		fi
	done
	
	ks_target="$BOOTCD_PATH/tools/profiles/$PROFILE/packages-$ks_name.lst"
	rm -f $ks_target 2>/dev/null
	echo -e "$GR_RESOLVED" | sed -e "/^$/d" | sort | uniq > $ks_target
	
	echo ""
	echo "Retrieving extra packages for profile $KS ..."
	#echo "    ▸ checking packages versions"
	#find_rpms_version "$RPMS2CHECK" RESOLV
	echo "    ▸ resolving \"$ks_name\" dependencies"
	#rpm_resolver "$RESOLV" "$ks_target"
	rpm_resolver "$RPMS2CHECK" "$ks_target"
	res=$?
	if [ $res -gt 0 ]; then
		exit 1
	fi
	
	echo ""
	TOT=`cat $ks_target | sort | uniq | wc -l`
	echo '###################################################'
	echo " Number of rpms for KS $ks_name: $TOT"
	echo '###################################################'
	perl -p -i -e "s/NUMBER_OF_RPMS=.*/NUMBER_OF_RPMS=$TOT/" $BOOTCD_PATH/$KS
}

function help() 
{
	echo ""
	echo "Usage: mkrpmdeps.sh -d <DIR> -p <PROF> -k <KS>"
	echo ""
	echo "Options:"
	echo "-h | --help )     help"
	echo "-d | --dest )     Destination directory"
	echo "-p | --profile )  ISO profile type"
	echo "-k | --ks )       Kickstart name"
	echo "-t | --test )     Test mode"
	echo "-f | --force )    Do not exit if package is missing"
	echo ""
}

function get_opts()
{
	BOOTCD_PATH="/opt/repo/system/6.5/rhel/os/x86_64"
	KS="ks_dev.cfg"
	PROFILE="ncx"

	DIR_OPT=false
	KS_OPT=false
	PROFILE_OPT=false
	TEST=false
	FORCE=false
	for i in $OPTS ; do
		if [ "$DIR_OPT" == true ]; then
			BOOTCD_PATH="$i"
			DIR_OPT=false
		elif [ "$PROFILE_OPT" == true ]; then
			PROFILE="$i"
			PROFILE_OPT=false
		elif [ "$KS_OPT" == true ]; then
			KS="$i"
			KS_OPT=false
		fi
		case $i in
			-h | --help )
				help
				exit 1 ;;
			-d | --dest ) DIR_OPT=true ;;
			-p | --profile ) PROFILE_OPT=true ;;
			-k | --ks ) KS_OPT=true ;;
			-t | --test ) TEST=true ;;
			-f | --force ) FORCE=true ;;
		esac
	done
}

### MAIN ###

OPTS=$@
get_opts

clean_repo
make_profile_list
res=$?
if [ $res -gt 0 ]; then
	exit 1
fi

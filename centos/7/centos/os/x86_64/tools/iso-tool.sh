#!/bin/sh

SCRIPT=$(readlink -e $0)
SCRIPTPATH=$(dirname $SCRIPT)
DISTRIB_DIR=$(dirname $SCRIPTPATH../)

function mod_kickstart()
{
	FILES=$(ls $DISTRIB_DIR/ks_*.cfg)
	DISTRIB="$DISTRIB_NAME $DISTRIB_VERSION"
	for ks_path in $FILES ; do
		ks=$(echo $ks_path  | sed -e "s/.*\///")
		echo "$ks: updating version"
		perl -p -i -e "s/VERSION=.*./VERSION=$NEW_VER/" $ks_path
		perl -p -i -e "s/DISTRIB=.*./DISTRIB=\"$DISTRIB\"/" $ks_path
		# Check Kickstart packages need
		echo "$ks: checking RPMs list"
		ks_name=$(echo $ks | sed -e "s/ks_//" | sed -e "s/.cfg//")
		KS_PACKAGES=$(grep -A200 "^%packages" $DISTRIB_DIR/$ks | grep -B200 "^%pre" | grep -v "^-" | grep -v "^#" | grep -v "^%packages\|^%pre\|^%end" | sort | uniq)
		if [ -f $DISTRIB_DIR/tools/kstools/$ks_name-rpms.lst ]; then
			PREVIOUS_PACKAGES="`cat $DISTRIB_DIR/tools/kstools/$ks_name-rpms.lst | sort | uniq`"
		else
			PREVIOUS_PACKAGES=""
		fi
		if [ "$PREVIOUS_PACKAGES" != "$KS_PACKAGES" ]; then
			echo "Running dependancies tool ..."
			if [ "$FORCE" == "TRUE" ]; then
				sh $DISTRIB_DIR/tools/kstools/mkrpmdeps.sh --force --dest "$DISTRIB_DIR" --ks "$ks" --profile "$PROFILE"
				local res=$?
			else
				sh $DISTRIB_DIR/tools/kstools/mkrpmdeps.sh --dest "$DISTRIB_DIR" --ks "$ks" --profile "$PROFILE"
				local res=$?
			fi
			if [ $res -gt 0 ]; then
				echo "An error occured during RPMs dependencies checking."
				echo "Aborting."
				exit 1
			fi
			NEW_PACKAGES=`grep -A200 "^%packages" $DISTRIB_DIR/$ks | grep -B200 "^%pre" | grep -v "^-" | grep -v "^#" | grep -v "^%packages\|^%pre\|^%end" | sort | uniq`
			echo -e "$NEW_PACKAGES" > $DISTRIB_DIR/tools/kstools/$ks_name-rpms.lst
		fi
		TOT=`cat $DISTRIB_DIR/tools/profiles/$PROFILE/packages-$ks_name.lst | sort | uniq | wc -l`
		perl -p -i -e "s/NUMBER_OF_RPMS=.*/NUMBER_OF_RPMS=$TOT/" $DISTRIB_DIR/$ks
		
	done

}

function notes2html()
{
	cat RELEASE-NOTES-en.html $PROF_DIR/releasenote.txt > tmp1.html
	echo "</br>" >> tmp1.html
	echo "</body>" >> tmp1.html
	echo "</html>" >> tmp1.html
	mv tmp1.html ../RELEASE-NOTES-en.html
}

function make_repository()
{
	cd $DISTRIB_DIR
	echo "Generating new repository ..."
	rm -f ./repodata/*.gz ./repodata/*.*.bz2 ./repodata/repomd.xml
	ls ./repodata/ | grep .*-$DIST_LOW-$ARCH-comps.xml | xargs -i -t mv repodata/{} repodata/$DIST_LOW-$ARCH-comps.xml
	createrepo -g repodata/$DIST_LOW-$ARCH-comps.xml .
	cd - 1>/dev/null 2>&1
	repoclosure --repofrompath=tmp,file:$DISTRIB_DIR -r tmp > $DISTRIB_DIR/tools/profiles/$PROFILE/unresolved
}

function mkiso()
{
	echo "mkisofs -f -l -o $DST/$ISONAME-$DIST-$NEW_VER-$SUFFIX-$ARCH.iso -r -J -V $DIST_LOW -p $DIST_LOW -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table $DISTRIB_DIR"
	mkisofs -f -l -o $DST/$ISONAME-$DIST-$NEW_VER-$SUFFIX-$ARCH.iso -r -J -V $DIST_LOW -p $DIST_LOW -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table $DISTRIB_DIR
	md5sum $DST/$ISONAME-$DIST-$NEW_VER-$SUFFIX-$ARCH.iso > $DST/MD5-$DIST-$NEW_VER-$SUFFIX-$ARCH.txt
	perl -pi -e "s/ .*\//  /" $DST/MD5-$DIST-$NEW_VER-$SUFFIX-$ARCH.txt
	ABS_DEST=$(readlink -m $DST/$ISONAME-$DIST-$NEW_VER-$SUFFIX-$ARCH.iso)
	echo "Built $DIST $NEW_VER $ARCH ISO image :"
	echo $ABS_DEST
}

function check_overwrite() {
	if [ "$FORCE" == "FALSE" ]; then
		if [ -e $DST/$ISONAME-$DIST-$NEW_VER-$SUFFIX-$ARCH.iso ]; then
			echo "The iso file version $NEW_VER already exist"
			echo -n "Do you wish to replace it ? [y/N]: "
			read line
			if [ "$line" != "y" -a "$line" != "Y" ]; then
				echo "Aborting iso creation"
				exit 1
			fi
		fi
	fi
}

function list_profiles()
{
	echo "Available ISO profiles:"
	ls $DISTRIB_DIR/tools/profiles/
	echo ""
}

function help() 
{
	echo ""
	echo "Usage: ./iso-tools.sh [-p <kvm>] [-d <dest_directory>] [-n <new_version_number>] :to create a new iso file"
	echo "       ./iso-tools.sh -h or --help                                    :to display this help"
	echo ""
	echo "Options:"
	echo "  -p | --profile <PROF>  : ISO profile type. Default is kvm."
	echo "  -n | --num     <VERS>  : Set version number."
	echo "                           By default it is fetched from releasenote."
	echo "  -d | --dest    <DIR>   : Destination directory."
	echo "  -a | --arch    <ARCH>  : Architecture. Default is fetched from path."
	echo "  -o | --os      <OS>    : Distribution type. Default is fetched from path."
	echo "  -c | --clean           : Clean rpm lists."
	echo "  -t | --test    <KS>    : Test a Kickstart profile. Use \"all\" to test all kickstarts."
	echo "  -f | --force           : Force ISO building even if there are missing packages."
	echo "  -r | --rebuild         : Rebuild ISO image without regenerating repository data."
	echo ""
	echo "Standalone Options:"
	echo "  -h | --help            : Show this help message."
	echo "  -l | --list            : Show available ISO profiles."
}

function get_opts()
{
	DIST='CENTOS7'
	DISTRIB_NAME="CentOS"
	DISTRIB_VERSION="7"
	tmp_dist=$(pwd | sed -e "s/\/os\/.*//" | sed -e "s/.*\///")
	tmp_ver=$(pwd | sed -e "s/.$tmp_dist.os.*//" | sed -e "s/.*\///" | sed -e "s/\..*//")
	if [ "$tmp_dist" -a "$tmp_ver" ]; then
		DIST=$(echo "$tmp_dist$tmp_ver" | tr '[:lower:]' '[:upper:]')
		DIST_LOW="$tmp_dist$tmp_ver"
		DISTRIB_VERSION=$tmp_ver
		DISTRIB_NAME=$tmp_dist
	else
		tmp_dist="centos"
		tmp_ver="7"
	fi
	if [ "$DISTRIB_NAME" == "centos" ]; then
		DISTRIB_NAME="CentOS"
	fi
	echo "$DISTRIB_NAME"
	
	TEST=""
	VALUE="FALSE"
	DIR="FALSE"
	ARCH_OPT="FALSE"
	OS_OPT="FALSE"
	PROFILE_OPT="FALSE"
	TEST_OPT="FALSE"
	FORCE="FALSE"
	REBUILD="FALSE"
	for i in $OPTS ; do
		if [ "$VALUE" == "TRUE" ]; then
			NEW_VER="$i"
			VALUE="FALSE"
		elif [ "$DIR" == "TRUE" ]; then
			DST=$(echo $i | sed -e "s/\/$//")
			DIR="FALSE"
		elif [ "$PROFILE_OPT" == "TRUE" ]; then
			PROFILE="$i"
			PROFILE_OPT="FALSE"
		elif [ "$ARCH_OPT" == "TRUE" ]; then
			ARCH="$i"
			ARCH_OPT="FALSE"
		elif [ "$OS_OPT" == "TRUE" ]; then
			DIST="$i"
			DIST_LOW=$(echo "$DIST" | tr '[:upper:]' '[:lower:]')
			OS_OPT="FALSE"
			if [ "$(echo $DIST | grep "RHEL")" ]; then
				DISTRIB_NAME="Redhat Entreprise Linux"
				DISTRIB_VER=$(echo $DIST | sed -e "s/RHEL//")
			elif [ "$(echo $DIST | grep "NETOS")" ]; then
				DISTRIB_NAME="NetOS"
				DISTRIB_VER=$(echo $DIST | sed -e "s/NETOS//")
			elif [ "$(echo $DIST | grep "CENTOS")" ]; then
				DISTRIB_NAME="CentOS"
				DISTRIB_VER=$(echo $DIST | sed -e "s/CENTOS//")
			else
				DISTRIB_NAME=$(echo $DIST | sed -e "s/[0-9]*//")
				DISTRIB_VER=$(echo $DIST | sed -e "s/[[:alpha:]]*//")
			fi
		elif [ "$TEST_OPT" == "TRUE" ]; then
			TEST="$i"
			TEST_OPT="FALSE"
		fi
		case $i in
			-h | --help )
				help
				exit 1 ;;
			-l | --list )
				list_profiles
				exit 1 ;;
			-n | --num ) VALUE="TRUE" ;;
			-d | --dest ) DIR="TRUE" ;;
			-p | --profile ) PROFILE_OPT="TRUE" ;;
			-a | --arch ) ARCH_OPT="TRUE" ;;
			-o | --os ) OS_OPT="TRUE" ;;
			-c | --clean ) CLEAN_OPT="TRUE";;
			-t | --test ) TEST_OPT="TRUE";;
			-f | --force ) FORCE="TRUE";;
			-r | --rebuild ) REBUILD="TRUE";;
		esac
	done
	
	if [ "$TEST_OPT" == "TRUE" ]; then
		TEST="all"
		TEST_OPT="FALSE"
	fi
	
	if [ -z "$PROFILE" ]; then
		PROFILE="kvm"
	fi
	
	PROF_DIR="$DISTRIB_DIR/tools/profiles/$PROFILE"
	if [ -e "$PROF_DIR/$PROFILE.ini" ]; then
		source $PROF_DIR/$PROFILE.ini
	else
		echo "Error: profile \"$PROFILE\" is not valid. Aborting."
		exit 1
	fi

	mkdir -p $DST

	NEW_VER=$(cat $PROF_DIR/releasenote.txt | grep "VERSION:" | head -n1 | sed -e "s/VERSION://" | sed -e "s/ *//")
	if [ -z "$NEW_VER" ]; then
		echo "Version not found, aborting !"
		exit 1
	fi
		
	if [ "$CLEAN_OPT" == "TRUE" ]; then
		rm -f $DISTRIB_DIR/tools/kstools/*.lst
		rm -rf $DISTRIB_DIR/groups
		rm -rf $PROF_DIR/*.lst
		rm -f $DISTRIB_DIR/ks_*.cfg 2>/dev/null
		rm -rf $DISTRIB_DIR/Extra
		rm -f $DISTRIB_DIR/repodata/*.gz 
		rm -f $DISTRIB_DIR/repodata/*.*.bz2 
		rm -f $DISTRIB_DIR/repodata/repomd.xml
		if [ "$PROFILE_OPT" == "FALSE" ]; then
			exit 0
		fi
	fi

	# Remove previous kickstarts
	rm -f $DISTRIB_DIR/ks_*.cfg 2>/dev/null
	# Copy profile's kickstarts
	if [ -z "$TEST" ] ;then 
		cp -a $PROF_DIR/ks_*.cfg $DISTRIB_DIR/ 2>/dev/null
	elif [ "$TEST" == "all" ]; then
		cp -a $PROF_DIR/ks_*.cfg $DISTRIB_DIR/ 2>/dev/null
		rm -rf $DISTRIB_DIR/tools/kstools/*.lst
		rm -rf $PROF_DIR/*.lst
	else
		if [ -f $PROF_DIR/ks_$TEST.cfg ]; then
			cp -a $PROF_DIR/ks_$TEST.cfg $DISTRIB_DIR/ 2>/dev/null
			rm -f $DISTRIB_DIR/tools/kstools/$TEST-rpms.lst
			rm -f $PROF_DIR/packages-$TEST.lst
		else
			echo "Profile \"$TEST\" does not exist !"
			exit 1
		fi
	fi

	if [ "$REBUILD" == "FALSE" ]; then
		rm -rf $DISTRIB_DIR/Extra
		if [ "$EXTRA" ]; then
			mkdir $DISTRIB_DIR/Extra
			for i in ${!EXTRA[*]}; do
				extra_repo=${EXTRA[i]}
				reponame=$(basename $extra_repo)
				echo "Adding repository \"$reponame\""
				mkdir -p $DISTRIB_DIR/Extra/$reponame
				ln -s $DISTRIB_DIR/$extra_repo/{noarch,$ARCH} $DISTRIB_DIR/Extra/$reponame/
				if [ -d $DISTRIB_DIR/$extra_repo/srpms ]; then
					ln -s $DISTRIB_DIR/$extra_repo/srpms $DISTRIB_DIR/Extra/$reponame/
				fi
			done
		fi
	fi
}

function get_base_dirs()
{

	pushd . > /dev/null
	SCRIPT_PATH="${BASH_SOURCE[0]}";
	while([ -h "${SCRIPT_PATH}" ]); do
		cd "`dirname "${SCRIPT_PATH}"`"
		SCRIPT_PATH="$(readlink "`basename "${SCRIPT_PATH}"`")";
	done
	cd "`dirname "${SCRIPT_PATH}"`" > /dev/null
	SCRIPT_PATH="`pwd`";
	popd  > /dev/null
	BASE="`dirname ${SCRIPT_PATH}../`"
	ARCH="x86_64"
	tmp_arch=`echo "${SCRIPT_PATH}" | sed -e "s/.tools//" | sed -e "s/.*\///"`
	if [ "$tmp_arch" ]; then
		ARCH=$tmp_arch
	fi
	
	DISTRIB_DIR=$BASE
	DST="`dirname $DISTRIB_DIR/../../isos/$ARCH/.`"
}

OPTS=$@
### MAIN ###
get_base_dirs
get_opts
check_overwrite

rm -rf $DISTRIB_DIR/.olddata
if [ "$REBUILD" == "FALSE" ]; then
	make_repository
fi
mod_kickstart
#copy_note
if [ -z "$TEST" ]; then
	rm -f $DISTRIB_DIR/isolinux/isolinux.cfg
	echo "Copying isolinux.cfg to $DISTRIB_DIR/isolinux/"
	cp -f $PROF_DIR/isolinux.cfg $DISTRIB_DIR/isolinux/isolinux.cfg
	notes2html
	cp $PROF_DIR/releasenote.txt $DST/releasenote-$DIST-$NEW_VER-$SUFFIX-$ARCH.txt
	mkiso
fi

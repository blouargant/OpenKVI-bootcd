#/bin/sh

if [ -z "$1" ]; then
	BOOTCD_PATH="/opt/repo/system/6.5/rhel/os/x86_64"
else
	BOOTCD_PATH=`echo $1 | sed -e "s/\/$//"`
fi

if [ -z "$2" ]; then
	group=""
else
	group="$2"
fi

if [ -z "$group" ]; then
	rm -rf $BOOTCD_PATH/repodata/groups 2>/dev/null
else
	rm -rf $BOOTCD_PATH/repodata/groups/$group 2/dev/null
fi
mkdir -p $BOOTCD_PATH/repodata/groups

COMPS_FILE=`find $BOOTCD_PATH/repodata/ -name "*comps*.xml"`

START=""
END=""
while read line; do
	if [ "$START" ]; then
		END=`echo $line | grep "</group>$"`
		if [ "$END" ]; then
			START=""
			ID=""
		else
			if [ "$ID" ]; then
				if [ "$ID" != "SKIP" ]; then
					RPM=`echo $line | grep "<packagereq type=.default\|<packagereq type=.mandatory" | sed -e "s/<\/packagereq>//" | sed -e "s/.*>//"`
					if [ "$RPM" ]; then
						echo $RPM >> $BOOTCD_PATH/repodata/groups/$ID
					fi
				fi
			else
				ID="`echo $line | grep "<id>.*</id>$" | sed -e "s/<\/id>.*//" | sed -e "s/.*>//"`"
				if [ "$group" ]; then
					if [ "$ID" != "$group" ]; then
						ID="SKIP"
					fi
				fi
			fi
				
		fi
		
	else
		START=`echo $line | grep "<group>$"`
		if [ "$START" ]; then
			END=""
			ID=""
		fi
	fi
	
done < $COMPS_FILE

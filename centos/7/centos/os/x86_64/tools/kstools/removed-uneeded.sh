#/bin/sh

if [ "$1" ]; then
	NEEDED_RPMS=$1
else
	echo "Please provides the list of needed rpms"
	exit 1
fi

RPMLIST=$(ls ../../Packages)
for RPM in $RPMLIST; do
	NAME=$(echo $RPM | sed -e "s/\.rpm$//")
	TEST=$(grep "^$NAME$" $NEEDED_RPMS)
	if [ -z "$TEST" ]; then
		rm -f ../../Packages/$RPM
	fi
done

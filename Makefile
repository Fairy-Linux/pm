install:
	cp pm /usr/bin/
	[ -d "/var/db/uninstall/" ] || mkdir /var/db/uninstall/ -p
	[ -d "/var/tmp/PackageManager/" ] || mkdir /var/tmp/PackageManager/
	touch /var/db/PackageManager.list

uninstall:
	rm /usr/bin/pm

clean:
	rm -rf /var/db/


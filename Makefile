install:
	cp pm /usr/bin/
	mkdir /var/db/uninstall/ -p
	mkdir /var/tmp/PackageManager/ -p
	touch /var/db/PackageManager.list

uninstall:
	rm /usr/bin/pm

clean:
	rm -rf /var/db/


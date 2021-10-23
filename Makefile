install:
	cp pm /usr/bin/
	mkdir /var/db/
	mkdir /var/tmp/PackageManager/

uninstall:
	rm /usr/bin/pm

clean:
	rm -rf /var/db/


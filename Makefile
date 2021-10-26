install:
	cp pm /usr/bin/
	touch /var/db/PackageManager.list

uninstall:
	rm /usr/bin/pm

clean:
	rm -rf /var/db/


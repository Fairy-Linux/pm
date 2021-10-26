#!/usr/bin/env bash

REPO="https://raw.githubusercontent.com/Fairy-Linux/dev-repos/main"
HELP="Fairy Linux Package Manager Help

h|help                 -> Displays this message!
i|install <package>    -> Installs a package
R|reinstall <package>  -> Reinstalls a package
r|remove <package>     -> Removes a package
s|show <package>       -> Gets information about a package
u|upgrade              -> Upgrades the system
l|list <all|installed> -> Lists the packages"

# Checks if the user is root or not, this will prevent most permission errors.
# Note - LOGNAME is used instead of $(whoami) to prevent spawning a subshell and increasing the speed of the package manager.
check_root() {
	if [[ ! "$LOGNAME" = "root" ]]; then
		echo "Please run as root!"
		exit 1
	fi
}

# For formatted and easier error handling.
error() {
	echo -e "\033[91m[ ERROR ] - $1 \033[0m"
	rm -rf "/var/tmp/PackageManager/$2/"
	exit 1
}

# Install function.
install_package() {
	# Checking if package exists or not
	if [[ $(curl -sSL -o /dev/null -I -w "%{http_code}" "$REPO/$1/hash" || error "Failed to fetch package information." "$1") -eq 404 ]]; then
		echo "\"$1\" package not found!"
		exit
	fi

	# Getting temporary directories ready for processing.
	# Note - /tmp is NOT used here due to it being a ramdisk. Large packages could easily choke the entire memor
	mkdir /var/tmp/PackageManager/"$1"/extraction/ -p || error "Failed to make temporary directory." "$1"

	# Mkdir /var/db/uninstall just in case it does not exist.
	mkdir /var/db/uninstall -p

	# Make package manager list just in case it does not exist.
	touch /var/db/PackageManager.list

	# A few variables for easier access
	temp=/var/tmp/PackageManager/"$1"
	temp_extract="$temp"/extraction
	tarball="$REPO"/"$1"/"$1".tar.zst
	files="$REPO/$1/files"
	hash="$REPO/$1/hash"

	# Downloading package files.
	curl "$tarball" -sSL -o "$temp"/"$1".tar.zst || error "Failed to fetch package." "$1"
	curl "$files" -sSL -o "$temp/files" || error "Failed to fetch package file list." "$1"
	curl "$hash" -sSL -o "$temp/hash" || error "Failed to fetch package hash." "$1"

	# Checking SHA256 hash of tarball and extracting it.
	if echo "$(cat $temp/hash) $temp/$1.tar.zst" | sha256sum --check --quiet; then
		echo "$1 tarball check: OK"
	else
		echo "$1 tarball check: ERR"
		error "Invalid SHA256 Sum of tarball, exiting." "$1"
	fi

	tar xf "$temp"/"$1".tar.zst -C "$temp_extract" || error "Failed to extract tarball." "$1"

	while read file; do
		if [[ "$file" == "*/" ]]; then
			mkdir "$file" -p
		else
			atomic_name="${file}_$$_PackageManagerInstall_${file##/*}"
			cp "$temp_extract$file" "$atomic_name"
			mv "$atomic_name" "$file"
			echo "$target" >>"/var/db/uninstall/$1" || error "Failed to add uninstall database information." "$1"
		fi
	done <"$temp/files"

	# Clear temporary directories
	rm -rf "$temp" || error "Failed to remove temporary directory."

	# Add database entry
	echo "$1" >>/var/db/PackageManager.list || error "Failed to add package to package database."
}

case $1 in
h | help)
	echo "$HELP"
	;;

i | install)
	check_root

	# Prevents re-installation.
	if grep -q "$2" /var/db/PackageManager.list; then
		echo "$2 is already installed."
		exit
	fi

	echo "Installing $2!"
	install_package "$2"
	echo "Installed $2"
	;;

R | reinstall)
	check_root

	echo "Reinstalling $2!"
	install_package "$2"
	echo "Reinstalled $2"
	;;

r | remove)
	check_root

	# Checking if package is installed in the first place.
	if ! grep -q "$2" /var/db/PackageManager.list; then
		echo "$2 is not installed."
		exit
	fi

	while read file; do
		rm -rf "$file" || error "Failed to remove file $file while uninstalling $2."
	done </var/db/uninstall/"$2"

	# Remove package from database.
	sed -i -e "s/$2//g" /var/db/PackageManager.list

	echo "Removed $2"
	;;

s | show)
	# Checking if package exists or not.
	if [[ $(curl -sSL -o /dev/null -I -w "%{http_code}" "$REPO/$2/hash" || error "Failed to fetch package information.") -eq 404 ]]; then
		echo "\"$1\" package not found!"
		exit
	fi

	# Information about the package.
	info=$(curl -sSL "$REPO/$2/info" || error "Failed to fetch package information.")
	name=$(echo "$info" | head -1 | tail -1)
	version=$(echo "$info" | head -2 | tail -1)
	description=$(echo "$info" | head -3 | tail -1)

	if grep -q "$2" /var/db/PackageManager.list; then
		installed="Yes."
	else
		installed="No."
	fi

	echo "Package name -> $name"
	echo "Version      -> $version"
	echo "Description  -> $description"
	echo "Installed    -> $installed"
	;;


	l | list)
	# List packages that are installed
	if [ "$2" = "installed" ]; then
		cat /var/db/PackageManager.list || error "Failed to print installed package list."
	elif [ "$2" = "all" ]; then
		curl -sSL "$REPO/list" || error "Failed to fetch package list."
	else
		echo "Invalid sub-command; $2"
	fi

	;;

*)
	echo "$HELP"
	;;

esac

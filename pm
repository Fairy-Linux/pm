#!/usr/bin/env bash

REPO="https://raw.githubusercontent.com/Fairy-Linux/dev-repos/main"
HELP="
Fairy Linux Package Manager Help

hp|help <command>       -> Provides help, optionally about a command
in|install <package>    -> Installs a package
re|reinstall <package>  -> Reinstalls a package
rm|remove <package>     -> Removes a package
up|upgrade <package>    -> Upgrades the system
sh|show <package>       -> Gets information about a package
ls|list <all|installed> -> Lists the packages
wp|provides <command>   -> Shows which package provides given command

"
DEPENDECIES=()

# So I can access it from inside functions. God damn it bash.
package="$2"

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
	echo "$(tput setaf 9)[ ERROR ] - $1$(tput sgr0)"
	rm -rf "/var/tmp/PackageManager/$2/"
	exit 1
}

# For checking if a package name is provided.
check_package() {
	if [[ -z "$package" ]]; then
		echo -e "\033[91m[ ERROR ] - Please specify a package.  \033[0m"
		exit
	fi
}


fetch_dependencies() {
	if [[ "$1" = "" ]]; then
		return 0
	fi
	DEPENDENCIES+=("$1")
	deps_fetched=$(curl -sSL "$REPO/$1/deps") || error "Failed to fetch dependencies." "$1"
	while read -r dep; do
		fetch_dependencies "$dep"
	done<<<"$deps_fetched"
}


# Install function.
install_package() {
	
	# Checking if package exists or not
	hash=$(curl -sSL "$REPO/$1/hash") || error "Failed to fetch package information." "$1"
	if [[ "$hash" = "404: Not Found" ]]; then
		echo "\"$1\" package not found!"
		exit
	fi

	# Getting temporary directories ready for processing.
	# Note - /tmp is NOT used here due to it being a ramdisk. Large packages could easily choke the entire memor
	mkdir /var/tmp/PackageManager/"$1"/extraction/ -p || error "Failed to make temporary directory." "$1"

	# Mkdir /var/db/uninstall just in case it does not exist.
	mkdir /var/db/uninstall -p

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
	if echo $(cat "$temp/hash") "temp/$1.tar.zst" | sha256sum --check --quiet; then
		echo "$1 tarball check: OK"
	else
		echo "$1 tarball check: ERR"
		error "Invalid SHA256 Sum of tarball, exiting." "$1"
	fi

	tar xf "$temp"/"$1".tar.zst -C "$temp_extract" || error "Failed to extract tarball." "$1"

	while read -r file; do
		if [[ "$file" == "*/" ]]; then
			mkdir "$file" -p
		else
			atomic_name="${file}_$$_PackageManagerInstall_${file##/*}"
			cp "$temp_extract$file" "$atomic_name"
			mv "$atomic_name" "$file"
			echo "$file" >>"/var/db/uninstall/$1" || error "Failed to add uninstall database information." "$1"
		fi
	done <"$temp/files"

	# Clear temporary directories
	rm -rf "$temp" || error "Failed to remove temporary directory."

	# Add database entry
	# $2 for this function shows that if the function is being called for reinstallation or not.
	if [[ ! "$2" = "r" ]]; then
		echo "$1" >> /var/db/PackageManager.list || error "Failed to add package to package database."
	fi
}

case "$1" in
hp | help)
	if [[ -z "$2" ]]; then
		echo "$HELP"
	else
		case "$2" in
			hp | help)
				echo "
Command     -> Help
Description -> Provides help on the package managers commands, optionally about a specific command.
Syntax      -> pm <hp|help> <command>
				"
			;;

			in | install)
				echo "
Command     -> Install
Description -> Installs packages on the system, optionally on an external rootfs using the DESTDIR env var.
Syntax      -> pm <in|install> <package>
				"
			;;

			re | reinstall)
				echo "
Command     -> Reinstall
Description -> Reinstalls packages on the system, optionally on an external rootfs using the DESTDIR env var.
Syntax      -> pm <re|reinstall> <package>
				"
			;;

			rm | remove)
				echo "
Command     -> Remove
Description -> Removes a package from the system.
Syntax      -> pm <rm|remove> <package>
				"
			;;

			up | upgrade)
				echo "
Command     -> Upgrade
Description -> Upgrades the system.
Syntax      -> pm <up|upgrade>
				"
			;;

			sh | show)
				echo "
Command     -> Show
Description -> Gives detailed information about a package.
Syntax      -> pm <sh|show> <package>
				"
			;;

			ls | list)
				echo "
Command     -> Remove
Description -> Lists either all packages installed on the system or all packages available on available repositories.
Syntax      -> pm <rn|remove> <all|installed>
				"
			;;

			wp | provides)
				echo "
Command     -> Provides
Description -> Provides package name which provides given command.
Syntax      -> pm <wp|provides> <command>
				"
			;;

			*)
				echo "$HELP"
			;;
		esac
	fi
	;;

in | install)
	check_root
	check_package

	# Prevents re-installation.
	if grep -q "$2" /var/db/PackageManager.list; then
		echo "$2 is already installed."
		exit
	fi

	# Provide user information about the packages about to be installed and confirm it.
	echo "Resolving package dependencies..."
		fetch_dependencies "$2"
		echo -e "\n$(tput setaf 3)The following packages are going to be installed -\n    ${DEPENDENCIES[*]}$(tput sgr0)"
		printf "%sAre you sure you want to continue with the installation? [y/N] %s" "$(tput setaf 2)" "$(tput sgr0)"
		read -r choice
		case "$choice" in 
			y | Y | Yes | yes)
			;;
	
			*)
				error "Program Aborted." "$2"
			;;
		esac	
	echo;

	# Make package manager list just in case it does not exist.
	touch /var/db/PackageManager.list
	
	install_package "$2"
	echo "Installed $2"
	;;

re | reinstall)	
	check_root
	check_package

	# Provide user information about the packages about to be installed and confirm it.
	echo "Resolving package dependencies..."
		fetch_dependencies "$2"
		echo -e "\n$(tput setaf 3)The following packages are going to be installed -\n    ${DEPENDENCIES[*]}$(tput sgr0)"
		printf "%sAre you sure you want to continue with the installation? [y/N] %s" "$(tput setaf 2)" "$(tput sgr0)"
		read -r choice
		case "$choice" in 
			y | Y | Yes | yes)
			;;
	
			*)
				error "Program Aborted." "$2"
			;;
		esac	
	echo;
	
	# Make package manager list just in case it does not exist.
	touch /var/db/PackageManager.list

	# for "package" in "$DEPENDENCIES[@]"
	# do
	
	# done
	install_package "$2" "r"
	echo "Reinstalled $2"
	;;

rm | remove)
	check_root
	check_package
	
	# Checking if package is installed in the first place.
	if ! grep -q "$2" /var/db/PackageManager.list; then
		echo "$2 is not installed."
		exit
	fi

	while read -r file; do
		rm -rf "$file" || error "Failed to remove file $file while uninstalling $2."
	done </var/db/uninstall/"$2"

	# Remove package from database.
	sed -i -e "/$2/d" /var/db/PackageManager.list

	echo "Removed $2"
	;;

sh | show)
	check_package
	
	# Checking if package exists or not.
	hash=$(curl -sSL "$REPO/$1/hash") || error "Failed to fetch package information." "$1"
	if [[ "$hash" = "404: Not Found" ]]; then
		echo "\"$1\" package not found!"
		exit
	fi

	# Information about the package.
	info=$(curl -sSL "$REPO/$2/info") || error "Failed to fetch package information." "$1"
	deps=$(curl -sSL "$REPO/$2/deps") || error "Failed to fetch dependencies." "$1"
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
	echo "Hash         -> $hash"
	echo "description  -> $deps"
	echo "Installed    -> $installed"
	;;


ls | list)
	# List packages that are installed
	if [ "$2" = "installed" ]; then
		cat /var/db/PackageManager.list || error "Failed to print installed package list."
	elif [ "$2" = "all" ]; then
		curl -sSL "$REPO/list" || error "Failed to fetch package list from remote repository."
	else
		echo "Invalid sub-command; $2"
	fi

	;;

*)
	echo "$HELP"
	;;

esac

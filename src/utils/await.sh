use std::async::await;

function await::for_vscode_ide_start() {
	if grep -q 'supervisor' /proc/1/cmdline; then {
		gp ports await 23000 1>/dev/null;
	} fi
}

function await::create_shim() {
	declare -a vars_to_unset=(SHIM_MIRROR SHIM_SOURCE KEEP_internal_call);
	declare +x CLOSE KEEP DIRECT_CMD; # Keep local, do not export into env
	export SHIM_MIRROR; # Reuse previoulsy exported SHIM_MIRROR before CLOSE'ing
	declare SHIM_HEADER_SIGNATURE="# AWAIT_CREATE_SHIM";
	declare TARGER_SHIM_HEADER_SIGNATURE="# TARGET_REDIRECT_SHIM";

	# shellcheck disable=SC2120
	function is::custom_shim() {
		test -v SHIM_MIRROR;
	}

	function revert_shim() {
		try_sudo touch "$shim_tombstone" || true;

		if ! is::custom_shim; then {
			if test -e "$shim_source"; then {
				try_sudo ln -sf "$shim_source" "$target";
			} fi
		} else {
				# try_sudo ln -sf "$shim_source" "$SHIM_MIRROR";
				# try_sudo ln -sf "$SHIM_MIRROR" "$target";
			if [[ "$shim_source" == *.nix-profile* ]]; then {
				(
					function main() {
						set -e
						if test -x "${shim_source:-}"; then
							: "$shim_source";
						elif test -x "${SHIM_MIRROR:-}"; then
							(sleep 10 && sudo rm -f "$0" 2>/dev/null) & disown;
							: "$SHIM_MIRROR";
						fi
						exec "$_" "$@";
					}
					body="$(
						printf '%s\n' '#!/usr/bin/env bash' "$TARGER_SHIM_HEADER_SIGNATURE" "$(declare -f main)";
						printf '%s="%s"\n' \
										"shim_source" "$shim_source" \
										SHIM_MIRROR "$SHIM_MIRROR";
						printf '%s "$@";\n' main;
					)"
					try_sudo env self="$body" target="$target" sh -c 'printf "%s\n" "$self" > "$target" && chmod +x $target';
				)
			} elif test -e "$shim_source"; then {
				try_sudo ln -sf "$shim_source" "$target";
			} fi
		} fi

		unset "${vars_to_unset[@]}";
		unset -f "$target_name";
		export PATH="${PATH//"${shim_dir}:"/}";

		(
			sleep 3;
			try_sudo rm -f "$shim_tombstone" || true;
			# if is::custom_shim; then {
			# 	try_sudo rm -f "$target" || true;
			# } fi
			# try_sudo rmdir --ignore-fail-on-non-empty "$shim_dir" 2>/dev/null || :;
		) & disown;
	}

	# shellcheck disable=SC2120
	function create_self() {
		declare +x NO_PRINT;
		cmd() {
			printf '%s\n' '#!/usr/bin/env bash' "$SHIM_HEADER_SIGNATURE" "$(declare -f main)" 'main "$@"'
		}
		if ! test -v NO_PRINT; then {
			cmd > "${1:-"${BASH_SOURCE[0]}"}";
		} else {
			cmd
		} fi
	}

	declare shim_dir shim_source shim_tombstone target="$1";
	declare target_name="${target##*/}";
	if ! is::custom_shim; then {
		shim_dir="${target%/*}/.ashim";
		shim_source="${shim_dir}/${target##*/}";
	} else {
		shim_dir="${SHIM_MIRROR%/*}/.cshim";
		shim_source="$shim_dir/${SHIM_MIRROR##*/}";
	} fi
	shim_tombstone="${shim_source}.tombstone";

	if test -v CLOSE; then {
		revert_shim;
		return;
	} fi
	
	if test -v KEEP && test ! -v KEEP_internal_call; then {
		export SHIM_SOURCE="$shim_source"; # for internal use
		export KEEP_internal_call=true;
	} fi

	# if ! [[ "$PATH" =~ "$shim_dir" ]]; then {
	# 	export PATH="$shim_dir:$PATH";
	# 	fn="$(
	# 		cat <<-EOF
	# 		function $target_name() {
	# 			if test -x "$shim_source"; then {
	# 				(
	# 					unset ${vars_to_unset[*]};
	# 					exec "$shim_source" "\$@";
	# 				)
	# 			} else {
	# 				command "$target" "\$@";
	# 			} fi
	# 		}
	# 		EOF
	# 	)" && eval "$fn" && unset fn && export -f "${target_name}";
	# } fi
	
	if test -v DIRECT_CMD; then {
		if shift; then {
			(
				unset "${vars_to_unset[@]}";
				"$@";
			)
		} fi
		return;
	} fi

	if test ! -v NOCLOBBER; then {
		if test -e "$target" && ! is::custom_shim; then {
			try_sudo mkdir -p "$shim_dir";
			try_sudo mv "$target" "$shim_source";
		} elif test -e "${SHIM_MIRROR:-}" && is::custom_shim; then {
			try_sudo mkdir -p "$shim_dir";
			try_sudo mv "$SHIM_MIRROR" "$shim_source";
		} fi
	} elif test -v NOCLOBBER && { test -e "$target" || test -e "${SHIM_MIRROR:-}"; }; then {
		log::warn "${FUNCNAME[0]}: $target already exists";
		return 0;
	} fi

	declare USER && USER="$(id -u -n)";
	try_sudo sh -c "mkdir -p \"${target%/*}\" && touch \"$target\" && chown $USER:$USER \"$target\"";

	# Embedded script
	function async_wrapper() {
		# DEBUG
		# if test -v DEBUG_TUX; then
		# 	set -x;
		# fi
		set -eu;

		# DEBUG
		# if test "${KEEP_internal_call:-}" == false; then {
		# 	trap 'printf "[%s]: %s\n" "${LINENO}" "$BASH_COMMAND" >> /tmp/log' DEBUG;
		# } fi

		# TODO: Improve this, too many garbage left behind
		# diff_target="/tmp/.diff_${RANDOM}.${RANDOM}";
		# if test ! -e "$diff_target"; then {
		# 	create_self "$diff_target";
		# } fi

		await_nowrite_executable() {
			declare input="$1";
			while lsof -F 'f' -- "$input" 2>/dev/null | grep -q '^f.*w$'; do
				sleep 0.5;
			done
			await::until_true test -x "$input";
		}

		await_nowrite_executable_symlink() {
			declare input="$1";
			await_nowrite_executable "$input";
			until test -L "$input" || {
				test "$(sed -n '2p;3q' "$input" 2>/dev/null)" == "$TARGER_SHIM_HEADER_SIGNATURE" \
				&& NO_AWAIT_SHIM=true
			}; do {
				sleep 0.5;
			} done
		}

		exec_bin() {
			local args=("$@");
			local bin="${args[0]}";
			await::until_true test -x "$bin";			
			# DEBUG
			unset "${vars_to_unset[@]}";
			export PATH="${bin%/*}:$PATH";
			exec "${args[@]}";
		}

		await_while_shim_exists() {
			if test -v NO_AWAIT_SHIM; then return; fi
			# DEBUG
			# if test "${KEEP_internal_call:-}" == false; then set -x; fi

			# Refer to revert_shim for this if-code-block
			if is::custom_shim; then {
				: "$target";
			} else {
				: "$shim_source";
			} fi

			local checkf="$_";

			for _i in {1..3}; do {
				sleep 0.2${RANDOM};
				while test -e "$checkf" && test ! -L "$checkf"; do sleep 0.5${RANDOM}; done
				# DEBUG
				# while test -e "$checkf"; do {
					# if test "${KEEP_internal_call:-}" == false; then
					# 	printf '============ %s\n' "CHEKF=$checkf" "$(ls "$target" ||:;)" "$(ls "$shim_source" ||:;)"
					# fi
					# sleep 0.5$RANDOM;
				# } done
				
			} done
		}

		if test -v AWAIT_SHIM_PRINT_INDICATOR; then {
			printf 'info[shim]: Loading %s\n' "$target";
		} fi

		# Reset target

		# Initial loop for detecting $target modifications
		## For KEEP=
		if test -e "$shim_source"; then {
			if test "${KEEP_internal_call:-}" == true; then {
				# When it's not the first time it was called, basically (2nd)
				exec_bin "$shim_source" "$@";
			} else {
				## For KEEP=
				# For external calls (2nd)
				await_while_shim_exists;
			} fi
		} elif ! is::custom_shim; then {
			# TIME="0.5${RANDOM}" await::while_true cmp --silent -- "$target" "$diff_target";
			while test "$(sed -n '2p;3q' "$target" 2>/dev/null)" == "$SHIM_HEADER_SIGNATURE"; do {
				sleep 0.5;
			} done
			# rm -f "$diff_target" 2>/dev/null || :;
			# TIME="0.5${RANDOM}" await_nowrite_executable_symlink "$target";
			await_nowrite_executable "$target";
		} else {
			# TIME="0.5${RANDOM}" await::for_file_existence "$SHIM_MIRROR";
			# await_nowrite_executable_symlink "$SHIM_MIRROR";

			# Refer to revert_shim for reasoning
			if test "${KEEP_internal_call:-}" == true; then {
				await_nowrite_executable "$SHIM_MIRROR";
			} else {
				await_nowrite_executable_symlink "$target";
			} fi
		} fi


		# For KEEP=
		if test -v KEEP_internal_call; then {
			# Create shim
			if test "${KEEP_internal_call:-}" == true; then {

				# For internal calls
				if test ! -e "$shim_tombstone" && test ! -e "$shim_source"; then {
						try_sudo mkdir -p "${shim_dir}";

						if ! is::custom_shim; then {
							try_sudo mv "$target" "$shim_source";
							try_sudo env self="$(NO_PRINT=true create_self)" target="$target" sh -c 'printf "%s\n" "$self" > "$target" && chmod +x $target';
						} else {
							try_sudo mv "${SHIM_MIRROR}" "$shim_source";
						} fi
				} fi

				if test -e "$shim_source"; then {
					exec_bin "$shim_source" "$@";
				} fi

			} else {
				# For external calls
				await_while_shim_exists;
			} fi

		} fi

		# At this point it's not not an KEEP_internal_call=true thing
		# if is::custom_shim; then {
		# 	# We need to revert some magic manually here for external calls when KEEP= wasn't used
		# 	# if ! test -v KEEP_internal_call; then
		# 	# 	revert_shim;
		# 	# fi
		# 	target="$SHIM_MIRROR"; # Set target to SHIM_MIRROR
		# } fi

		exec_bin "$target" "$@";
	}

	# Async shim script creation
	{
		printf 'function main() {\n';
		printf '%s="%s"\n' \
							target "$target" \
							shim_source "$shim_source" \
							shim_dir "$shim_dir"\
							SHIM_HEADER_SIGNATURE "$SHIM_HEADER_SIGNATURE" \
							TARGER_SHIM_HEADER_SIGNATURE "$TARGER_SHIM_HEADER_SIGNATURE";

		printf '%s=(%s)\n' vars_to_unset "${vars_to_unset[*]}";
		if test -v SHIM_MIRROR; then {
			printf '%s="%s"\n' SHIM_MIRROR "$SHIM_MIRROR";
		} fi
		# For KEEP=
		if test -v KEEP; then {
			printf '%s="%s"\n' \
								"KEEP_internal_call" '${KEEP_internal_call:-false}' \
								shim_tombstone "$shim_tombstone";
		} fi

		printf '%s\n' "$(declare -f await::while_true await::until_true await::for_file_existence sleep is::custom_shim try_sudo create_self async_wrapper)";
		printf '%s\n' 'async_wrapper "$@"; }';
	} > "$target";

	(
		source "$target";
		create_self "$target";
	)

	chmod +x "$target";
}

function await::create_shim_nix_common_wrapper() {
	declare name="$1";
	if is::cde; then {
		declare check_file=(/nix/store/*-"${name}"-*/bin/"${name}");

		# Lock on binary
		if test -n "${check_file:-}"; then {
			exec_path="${check_file[0]}";
			KEEP=true await::create_shim "$exec_path";
		} else {
			exec_path="/usr/bin/${name}";
			KEEP="true" SHIM_MIRROR="$HOME/.nix-profile/bin/${name}" \
				await::create_shim "$exec_path";
		} fi
	} else {
		await::until_true command::exists "$HOME/.nix-profile/bin/${name}";
	} fi
}
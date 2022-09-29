function config::neovim() {
	log::info "Setting up Neovim";

	# Wait for nix to complete installing neovim at userland_tools.sh:leveltwo_pkgs
	await::until_true command -v nvim 1>/dev/null;

	# Install LunarVim as an example config
	if test ! -e "$HOME/.config/lvim"; then {
		# git clone --filter=tree:0 https://github.com/axonasif/NvChad "$nvim_conf_dir" >/dev/null 2>&1;
		curl -sL "https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh" | bash -s -- --no-install-dependencies -y >/dev/null 2>&1;
	} fi

	# for _t in {1..2}; do {
	# 	nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync' 1>/dev/null;
	# } done

	if is::gitpod || is::codespaces; then {
		# Wait for tmux to start
		await::signal get config_tmux;

		# Run 'nvim --version' on tmux first window
		tmux send-keys -t "${tmux_first_session_name}:${tmux_first_window_num}" "nvim --version" Enter;
	} fi
}
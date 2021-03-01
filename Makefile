m.fish: u2dl.fish
	@wc -c $@
	time ./minify.fish $< >$@
	@wc -c $@

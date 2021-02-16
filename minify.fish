#!/usr/bin/env fish

set ident_num 0
set ident_chars (string split "" "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
function gen_ident
	set -l ident ""
	set -l n $ident_num
    
    while true
		set -a ident $ident_chars[(math $n % 52 + 1)]
        set n (math -s0 $n / 52)
        
        test $n -eq 0 && break
    end

    set ident_num (math $ident_num + 1)
    string join "" $ident
end

if test (count $argv) -ne 1 || not test -f $argv[1]
 	echo "usage:" (status -f) "<filename>" >&2; exit 1
end

set -l rules ""
set -l content (cat $argv[1] | #tr ';' '\n' |
sed -E '/#!MINIFIER_ELIDE/,/#!MINIFIER_ELIDE_END/d;
s/#!!//g; s/#.*//g; /^$/d' | string collect)
set -l cls_ident_char '[_a-zA-Z]'
set -l cls_not_ident_char '[^_a-zA-Z]'
set -l grp_progn_flags '(--?[a-zA-Z]+ )*'

set idents (echo $content | sed -nE 's/.*((set '$grp_progn_flags')|for |alias )('$cls_ident_char'+) .*/\4/gp' | sort -u)
set -a idents 'set' # minify `set` calls
set -l new_set_ident ""
for ident in $idents
	set -l new_ident (gen_ident)
    while grep -oE "set $grp_progn_flags$new_ident$not_ident_char" (echo $content | psub) >/dev/null
		set new_ident (gen_ident)
    end

    if test "$ident" = "set"
		set new_set_ident $new_ident
    end
	echo $ident -\> $new_ident >&2
    # general variable rules
	set -a rules "s/\\\$$ident(($cls_not_ident_char)|\$)/\$$new_ident\2/g" # $ident -> $new_ident
	set -a rules "s/.*(set $grp_progn_flags)$ident($cls_not_ident_char)/\1$new_ident\3/g"

    # `for` rules
    set -a rules "s/for $ident in/for $new_ident in/g"

    # `alias` rules
    set -a rules "s/alias $ident /alias $new_ident /g"
    set -a rules "s/(^|([^_A-zA-Z\"']))$ident([\); ]|\$)/\2$new_ident\3/g" # NB: ugly hack! ", '
end

#string join ";" $rules[2..-1] >&2
#echo "NEW SET IDENT" $new_set_ident >&2
#echo "RULES" $rules >&2


# remove leading whitespace
set -a rules 's/^['\t' ]+//g' 

set -a rules 's/ \| /\|/g' # compress pipes
set -a rules 's/ *([>]) */\1/g' # compress symbols

# apply one by one -- there's some sed parsing issue when we join the statements
for rule in $rules[2..-1]
	set content (echo $content | sed -E $rule | string collect)
end

# e e 'alias' ... -> e
set new_alias_ident (echo $content | sed -En 's/('$cls_ident_char'+) '$cls_ident_char'+ \'alias\'.*/\1/p')
echo $new_alias_ident >&2
echo $content | sed "1a\\
$new_alias_ident $new_set_ident 'set -g';" | tr '\n' ';' |
#echo 's/('$cls_ident_char'+) \1 \'alias\';alias/alias \1 \'alias\';\1/' >&2

# compressing the `set` usage of `alias` and fixing the `alias` definition
# e e 'alias'; -> alias e 'alias';
sed -E "s/$new_alias_ident $new_alias_ident 'alias'/alias $new_alias_ident 'alias'/" |
sed -E 's/;+/;/g; s/;$//'
#echo $content | sed -E (string join ";" $rules[2..-1])

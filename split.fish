#!/usr/bin/env fish

set in $argv[1]
for x in (seq 0 (math -s0 \((stat -f '%z' $in)\) / 280))
	echo -e (set_color -u cyan)"\nnumber $x"(set_color normal)
	cat $argv[1] | dd if=/dev/stdin of=/dev/stdout bs=1 skip=(math $x '*' 280) count=280 2>/dev/null | tee /dev/
    
end

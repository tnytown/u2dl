#!/usr/bin/env fish
#set URL "@https://www.youtube.com/watch?v=LeZ3EAFgPr8"
#set URL "https://www.youtube.com/watch?v=j1hft9Wjq9U"
#set URL "https://www.youtube.com/watch?v=X1b3C2081-Q"
#set URL 'https://www.youtube.com/watch?v=EUoe7cf0HYw'

# hints for the minifier
#!!alias alias 'alias'
#!!alias echo 'echo'
#!!alias math 'math'

# string: issues with piping, disable hints
##!!alias string 'string'

#alias end 'end'
alias jr 'jq -re'
alias sd 'sed -nE'

function p
	read -l x
    #echo -n arg: $argv[1], data: ''
    #printf -- (echo $data | sd "s/%/\\\x/g; s/.*$argv[1]=([^&]*).*/\1/p") >&2
    printf -- (echo $x | sd "s/%/\\\x/g;s/.*$argv[1]=([^&]*).*/\1/p")
end

set URL $argv[1]
set vid_id (echo $URL | p 'v')

set cipherPath '.signatureCipher'
#set curl_args -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.16; rv:84.0) Gecko/20100101 Firefox/84.0" -fsL
set curl_args -A "Mozilla/5.0 (Windows NT 6.3; Win64; x64; rv:80.0) Gecko/20100101 Firefox/80.0" -fsL

set page (curl $curl_args $URL || exit 1)

set player_config (echo $page | sd 's/.*ytInitialPlayerResponse = \{(.+)\};/\{\1\}/p')
set player_js (curl $curl_args www.youtube.com/(echo $page | sd 's/.*"([^"]+base.js).*/\1/p') || exit 1)

set fmts (echo $player_config | jr '.streamingData.adaptiveFormats | sort_by(-.bitrate)')

# debugging constructs
echo $page >page.html
echo $player_config >config.json
echo $player_js >player.js

# useful regex fragment(s)
# ){...}
set match_fn_body '\)\{([^\}]+).*' # NB: this breaks if the matched function has any blocks in it.

# NB: the Closure Compiler potentially uses $ in variable names, so we need to escape those.
set transform_fn (echo $player_js | sd 's/\$/\\\$/g;s/.*alr.*yes.*=(.*)\(dec.*/\1/p') # | sed 's/\$/\\\$/g'
set transform_fn_body (string split ';' (echo $player_js | sd "s/.*$transform_fn=function\(a$match_fn_body/\1/p"))

set transform_fn_body $transform_fn_body[2..-2]
for fmt in video audio
	set stream_data (echo $fmts | jr '[.[] | select(.mimeType | test("'$fmt'"))][0]')

    #!MINIFIER_ELIDE
    echo $stream_data | jq >&2
    if test -z "$stream_data"
		exit 2
	end
    #!MINIFIER_ELIDE_END

    set sig_ok (echo $stream_data | jr $cipherPath >/dev/null; echo $status)
    #echo $sig_ok >&2
    set url (if test $sig_ok -ne 0
		# w/o sig: url is 'url' field in json
		echo $stream_data | jr '.url'
    else
		# with sig: url is 'url' parameter in 'signatureCipher' json field
		echo -n $stream_data | jr $cipherPath | p 'url'
        echo \&sig=(
		set sig (echo $stream_data | jr $cipherPath | p 's')
        #echo transform_fn: $transform_fn, transform_fn_body: $transform_fn_body >&2
		for transform in $transform_fn_body
			# var,...
			set arg (echo $transform | sd 's/[^,]+,([0-9]+)\)/\1/p')
			set transform_call (echo $transform | sd 's/\(.*$//;s/\./\.\*/p')
			set pttn (echo $player_js | sd "s/.*$transform_call:function[^\)]+$match_fn_body/\1/p")
			set sig (switch $pttn
				case 'a.rev*'
					echo $sig | rev
				case 'var c=a*'
					set sig (echo $sig | string split '')
					set arg (math $arg%(count $sig)+1)
					set chr $sig[1]
					set sig[1] $sig[$arg]
					set sig[$arg] $chr
					string join '' $sig
				case 'a.spl*'
					set sig (echo $sig | string split '')
                    # TODO(aptny): pipe input instead of passing as args?
					string join '' $sig[(math $arg+1)..-1]
			end)
		end
        echo $sig)
    end)
    
	set blk 1048576
	set lft (echo $stream_data | jr '.contentLength')
	set max $lft
    
    cat (for blk_num in (seq 0 (math -s0 $max/$blk))
		set off (if test $lft -lt $blk
			echo $lft
        else
			echo $blk
        end)
        set low (math $max-$lft)
        
		curl $curl_args -o $blk_num.$fmt.$vid_id $url\&range=$low-(math $low+$off)&
        set lft (math $lft-$off-1)
        while test (jobs | wc -l) -ge 8
            wait -n curl
        end
		echo -ne "\r$low" >&2
        echo $blk_num.$fmt.$vid_id
    end
    wait) >$fmt.$vid_id
    echo "...$fmt ok" >&2
end
ffmpeg -i video.$vid_id -i audio.$vid_id -c copy $vid_id.mkv
rm *.$vid_id

#echo (echo $audio | jr '.signatureCipher' | urlp url)\&sig=$sig\&range=0-(echo $audio | jr '.contentLength')




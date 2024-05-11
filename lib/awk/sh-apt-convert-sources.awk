# Convert an APT source list from deb822 style to one-line style
#
/^[[:blank:]]*$/ {
	report()
	next
}

{
	$1 = tolower($1)
}

$1 == "uris:" {
	uri = $2
}

$1 == "types:" {
	add(types)
}

$1 == "suites:" {
	add(suites)
}

$1 == "components:" {
	add(components)
}

END {
	report()
}


function add(arr, _i)
{
	remove(arr)
	for (_i = 2; _i <= NF; _i++) {
		arr[_i] = $_i
	}
}

function remove(arr, _i)
{
	for (_i in arr) {
		delete arr[_i]
	}
}

function report(_t, _s, _c)
{
	if (! uri) {
		reset()
		return
	}
	for (_t in types) {
		for (_s in suites) {
			for (_c in components) {
				print types[_t], uri, suites[_s], components[_c]
			}
		}
	}
	reset()
}

function reset()
{
	uri = ""
	remove(types)
	remove(suites)
	remove(components)
}

// This is an example of a naked function
// similar to C++.  In C++ a naked function is a global
// function that does not belong to any class (like main())


transformExample = function(tx, ty)
{
    var transformVec2 = [tx,ty];
    return "test";
}



colorForStateNumber = function(st)
{
    switch(st) {
	    case 0:
	        return "#111111";
	        break;
	    case 1:
	        return "#666666";
	        break;
	    default:
	        return "#00ff00";
	        break;
	}
	return "#00ff00";
}


hsvColorForStateNumber = function(max_range, val, mult=0, mod=0, sat=0, lum=0) {

  var degrees = val / max_range;
  degrees = Math.round(degrees*360);

  var out = "hsl(" + degrees + " , 100%, 75%)";
  // out = "hsl(120, 100%, 25%)";

  return out;
}

gainForUid = function(uid) {
    var vec_range = 3000000;
    var s = uid - vec_range;
    
    var a = s % 1000;

    var gain;

    switch(a) {
        case 0:
            gain = 20;
            break;
        case 1:
            gain = 0.60;
            break;
        default:
            gain = 1;
            break;
    }

    return gain;
}


nameForVectorUid = function(uid) {
    // return "foo ";
    // return "foo " + uid;

    var vec_range = 3000000;
    var s = uid - vec_range;
    
    var a = s % 1000;
    var rid = Number.parseInt(s / 1000);

    var r = "R" + rid + ": ";

    var tag;

    switch(a) {
        case 0:
            tag = "channel_angle"
            break;
        case 1:
            tag = "channel_angle_sent"
            break;
        default:
            tag = "??";
            break;
    }

    return r + tag;

    // return "uid: " + uid + " s " + s + " a " + a + " rid " + rid;

}

gainForMax = function(curMax) {
    let factor = 62.8;

    // larger is smaller
    return factor/curMax;
}
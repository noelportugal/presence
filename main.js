var noble = require('noble');
var request = require('request');
function puts(error, stdout, stderr) { sys.puts(stdout) }

var url = 'http://smartoffice-engineservice.rhcloud.com/api/presence/' //in?v=123:123:123:12';

var rrsiThreshold = -60;
var state = "out";

noble.on('stateChange', function(state) {
  if (state === 'poweredOn')
    noble.startScanning([], true);
  else
    noble.stopScanning();
});

noble.on('discover', function(peripheral) {
    //console.log(peripheral.address + ' ' + peripheral.advertisement.localName + ' ' + peripheral.rssi);
    if (peripheral.advertisement.localName == 'iPhone7'){
      if (peripheral.rssi > rrsiThreshold && state == "out"){
          console.log("in");
          sendMessage('in', peripheral.address);
          state="in";
      }else if (peripheral.rssi < rrsiThreshold && state == "in"){
          console.log("out");
          sendMessage('out', peripheral.address);
          state="out";
      }
    }
});


// Handle clean exit event
process.stdin.resume();//so the program will not close instantly
function exitHandler(options, err) {
    console.log('stopScanning & exit');
    noble.stopScanning();
    process.exit();
}
// catches ctrl+c event
process.on('SIGINT', exitHandler.bind(null, {exit:true}));

function sendMessage(state, mac){
  request(url + state + '?v=' + mac, function (error, response, body) {
  if (!error && response.statusCode == 200) {
    console.log(body) // Show the HTML for the Google homepage.
  }
  })
}

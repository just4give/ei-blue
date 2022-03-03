
/**
This prorgam is written to collect IMU data from XIAO BLE Sense and send to EI Blue mobile app. 
EI Blue mobile app uploads the data to Edge Impulse Studio.
Visit https://wiki.seeedstudio.com/XIAO-BLE-Sense-Bluetooth-Usage/ to setup Arduino IDE 
Get EI Blue mobile app from https://github.com/just4give/ei-blue 
*/
#include <ArduinoBLE.h>
#include <LSM6DS3.h>
#include <Wire.h>

#define BLENAME                       "XIAO"
#define SERVICE_UUID                  "4D7D1101-EE27-40B2-836C-17505C1044D7"
#define TX_CHAR_UUID                  "4D7D1102-EE27-40B2-836C-17505C1044D7"
#define RX_CHAR_UUID                  "4D7D1103-EE27-40B2-836C-17505C1044D7"
#define SAMPLING_RATE                 50   //Hz
#define DURATION                      1 //seconds


BLEService bleService(SERVICE_UUID); // Bluetooth® Low Energy LED Service

// Bluetooth® Low Energy LED Switch Characteristic - custom 128-bit UUID, read and writable by central
BLEStringCharacteristic rxCharacteristic(RX_CHAR_UUID, BLEWrite, 1024);
BLEStringCharacteristic txCharacteristic(TX_CHAR_UUID, BLERead | BLENotify, 1024);

LSM6DS3 myIMU(I2C_MODE, 0x6A);    //I2C device address 0x6A
float aX, aY, aZ, gX, gY, gZ;
const float accelerationThreshold = 2.5; // threshold of significant in G's
int numSamples = 0;
int samplesRead = numSamples;



void setup() {
  Serial.begin(9600);
  
  // set LED pin to output mode
  pinMode(LEDB, OUTPUT);
  pinMode(LEDR, OUTPUT);
  pinMode(LEDG, OUTPUT);
  digitalWrite(LEDR, HIGH);
  digitalWrite(LEDB, HIGH);
  digitalWrite(LEDG, LOW);
  // begin initialization
  if (!BLE.begin()) {
    Serial.println("starting Bluetooth® Low Energy module failed!");

    while (1);
  }

  // set advertised local name and service UUID:
  BLE.setLocalName(BLENAME);
  BLE.setDeviceName(BLENAME);
  BLE.setAdvertisedService(bleService);

  // add the characteristic to the service
  bleService.addCharacteristic(txCharacteristic);
  bleService.addCharacteristic(rxCharacteristic);

  // add service
  BLE.addService(bleService);

  BLE.setEventHandler(BLEConnected, blePeripheralConnectHandler);
  BLE.setEventHandler(BLEDisconnected, blePeripheralDisconnectHandler);

  rxCharacteristic.setEventHandler(BLEWritten, rxCharacteristicWritten);
  // set the initial value for the characeristic:
  txCharacteristic.writeValue("");

  // start advertising
  BLE.advertise();

  Serial.println("BLE Peripheral");

  if (myIMU.begin() != 0) {
    Serial.println("Device error");
  } else {
    Serial.println("aX,aY,aZ,gX,gY,gZ");
  }

}

void loop() {
  BLE.poll();
}

void blePeripheralConnectHandler(BLEDevice central) {
  // central connected event handler
  Serial.print("Connected event, central: ");
  Serial.println(central.address());
  digitalWrite(LEDB, LOW);
  digitalWrite(LEDG, HIGH);
  digitalWrite(LEDR, HIGH);
}

void blePeripheralDisconnectHandler(BLEDevice central) {
  // central disconnected event handler
  Serial.print("Disconnected event, central: ");
  Serial.println(central.address());
  digitalWrite(LEDB, HIGH);
  digitalWrite(LEDG, LOW);
  digitalWrite(LEDR, HIGH);
}

void rxCharacteristicWritten(BLEDevice central, BLECharacteristic characteristic) {
  // central wrote new value to characteristic, update LED
  String value = rxCharacteristic.value();

  Serial.println("Characteristic event, written: "+ value);

  if (value.charAt(0) == 'S') {
    
    digitalWrite(LEDR, LOW);
    digitalWrite(LEDG, HIGH);
    digitalWrite(LEDB, HIGH);
    samplesRead =0;
    String data ="";
    int duration  = value.charAt(1) - '0';
    Serial.println(duration);

    numSamples = SAMPLING_RATE * duration;
    while (samplesRead < numSamples) {
    
    data = String(samplesRead*SAMPLING_RATE)+","+ String(myIMU.readFloatAccelX(), 3)+","+String(myIMU.readFloatAccelY(), 3)+","+String(myIMU.readFloatAccelZ(), 3);
    data = data + ","+ String(myIMU.readFloatGyroX(), 3)+","+String(myIMU.readFloatGyroY(), 3)+","+String(myIMU.readFloatGyroZ(), 3);
    delayMicroseconds(1000*1000/SAMPLING_RATE);
    samplesRead++;
    txCharacteristic.writeValue(data);
    

    if (samplesRead == numSamples) {
      // add an empty line if it's the last sample
      Serial.println();
      txCharacteristic.writeValue(";");
      digitalWrite(LEDR, HIGH);
      digitalWrite(LEDG, HIGH);
      digitalWrite(LEDB, LOW);
    }
  }
    Serial.println(data);

    
  } 
}
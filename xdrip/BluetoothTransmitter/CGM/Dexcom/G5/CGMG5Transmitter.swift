import Foundation
import CoreBluetooth
import os

class CGMG5Transmitter:BluetoothTransmitter, CGMTransmitter {
    
    // MARK: - public properties
    
    /// G5 or G6 transmitter firmware version - only used internally, if nil then it was  never received
    ///
    /// created public because inheriting classes need it
    var firmware:String?
    
    /// G5 or G6 age - only used internally, if nil then it was  never received
    ///
    /// created public because inheriting classes need it
    var transmitterStartDate: Date?
    
    /// CGMG5TransmitterDelegate
    public weak var cGMG5TransmitterDelegate: CGMG5TransmitterDelegate?

    // MARK: UUID's
    
    /// advertisement
    let CBUUID_Advertisement_G5 = "0000FEBC-0000-1000-8000-00805F9B34FB"
    
    /// service
    let CBUUID_Service_G5 = "F8083532-849E-531C-C594-30F1F86A4EA5"
    
    /// characteristic uuids (created them in an enum as there's a lot of them, it's easy to switch through the list)
    private enum CBUUID_Characteristic_UUID:String, CustomStringConvertible  {
        
        /// Read/Notify characteristic
        case CBUUID_Communication = "F8083533-849E-531C-C594-30F1F86A4EA5"
        
        /// Write/Indicate - write characteristic
        case CBUUID_Write_Control = "F8083534-849E-531C-C594-30F1F86A4EA5"
        
        /// Read/Write/Indicate - Read Characteristic
        case CBUUID_Receive_Authentication = "F8083535-849E-531C-C594-30F1F86A4EA5"
        
        /// Read/Write/Notify
        case CBUUID_Backfill = "F8083536-849E-531C-C594-30F1F86A4EA5"

        //// for logging, returns a readable name for the characteristic
        var description: String {
            switch self {
                
            case .CBUUID_Communication:
                return "Communication"
                
            case .CBUUID_Write_Control:
                return "Write_Control"
                
            case .CBUUID_Receive_Authentication:
                return "Receive_Authentication"
                
            case .CBUUID_Backfill:
                return "Backfill"
                
            }
        }
    }

    // MARK: other
    
    /// the write and control Characteristic
    private var writeControlCharacteristic:CBCharacteristic?
    
    /// the receive and authentication Characteristic
    private var receiveAuthenticationCharacteristic:CBCharacteristic?
    
    /// the communication Characteristic
    private var communicationCharacteristic:CBCharacteristic?
    
    /// the backfill Characteristic
    private var backfillCharacteristic:CBCharacteristic?

    //timestamp of last reading
    private var timeStampOfLastG5Reading:Date
    
    //timestamp of transmitterReset
    private var timeStampTransmitterReset:Date
    
    /// transmitterId
    private let transmitterId:String

    /// will be used to pass back bluetooth and cgm related events
    private(set) weak var cgmTransmitterDelegate:CGMTransmitterDelegate?
    
    /// for trace
    private let log = OSLog(subsystem: ConstantsLog.subSystem, category: ConstantsLog.categoryCGMG5)
    
    /// is G5 reset necessary or not
    private var G5ResetRequested:Bool
    
    /// used as parameter in call to cgmTransmitterDelegate.cgmTransmitterInfoReceived, when there's no glucosedata to send
    var emptyArray: [GlucoseData] = []
    
    /// for creating testreadings
    private var testAmount:Double = 150000.0
    
    //// true if pairing request was done, and waiting to see if pairing was done
    private var waitingPairingConfirmation = false
    
    /// to swap between request firmware or battery
    private var requestFirmware = true
    
    /// backFillStream
    private var backFillStream = DexcomBackfillStream()

    // MARK: - functions
    
    /// - parameters:
    ///     - address: if already connected before, then give here the address that was received during previous connect, if not give nil
    ///     - name : if already connected before, then give here the name that was received during previous connect, if not give nil
    ///     - transmitterID: expected transmitterID, 6 characters
    ///     - bluetoothTransmitterDelegate : a NluetoothTransmitterDelegate
    ///     - cGMTransmitterDelegate : a CGMTransmitterDelegate
    ///     - cGMG5TransmitterDelegate : a CGMG5TransmitterDelegate
    ///     - transmitterStartDate : transmitter start date, optinoal
    init(address:String?, name: String?, transmitterID:String, bluetoothTransmitterDelegate: BluetoothTransmitterDelegate, cGMG5TransmitterDelegate: CGMG5TransmitterDelegate, cGMTransmitterDelegate:CGMTransmitterDelegate, transmitterStartDate: Date?, firmware: String?) {
        
        // assign addressname and name or expected devicename
        var newAddressAndName:BluetoothTransmitter.DeviceAddressAndName = BluetoothTransmitter.DeviceAddressAndName.notYetConnected(expectedName: "DEXCOM" + transmitterID[transmitterID.index(transmitterID.startIndex, offsetBy: 4)..<transmitterID.endIndex])
        if let address = address {
            newAddressAndName = BluetoothTransmitter.DeviceAddressAndName.alreadyConnectedBefore(address: address, name: name)
        }
        
        // set timestampoflastg5reading to 0
        self.timeStampOfLastG5Reading = Date(timeIntervalSince1970: 0)
        
        //set timeStampTransmitterReset to 0
        self.timeStampTransmitterReset = Date(timeIntervalSince1970: 0)

        //assign transmitterId
        self.transmitterId = transmitterID
        
        // initialize G5ResetRequested
        self.G5ResetRequested = false
        
        // initalize transmitterStartDate
        self.transmitterStartDate = transmitterStartDate
        
        // initialize firmware
        self.firmware = firmware

        // initialize - CBUUID_Receive_Authentication.rawValue and CBUUID_Write_Control.rawValue will probably not be used in the superclass
        super.init(addressAndName: newAddressAndName, CBUUID_Advertisement: CBUUID_Advertisement_G5, servicesCBUUIDs: [CBUUID(string: CBUUID_Service_G5)], CBUUID_ReceiveCharacteristic: CBUUID_Characteristic_UUID.CBUUID_Receive_Authentication.rawValue, CBUUID_WriteCharacteristic: CBUUID_Characteristic_UUID.CBUUID_Write_Control.rawValue, bluetoothTransmitterDelegate: bluetoothTransmitterDelegate)

        //assign CGMTransmitterDelegate
        self.cgmTransmitterDelegate = cGMTransmitterDelegate
        
        // assign cGMG5TransmitterDelegate
        self.cGMG5TransmitterDelegate = cGMG5TransmitterDelegate
        
    }
    
    /// for testing , make the function public and call it after having activate a sensor in rootviewcontroller
    ///
    /// amount is rawvalue for testreading, should be number like 150000
    private func temptesting(amount:Double) {
        testAmount = amount
        Timer.scheduledTimer(timeInterval: 60 * 5, target: self, selector: #selector(self.createTestReading), userInfo: nil, repeats: true)
    }
    
    /// for testing, used by temptesting
    @objc private func createTestReading() {
        let testdata = GlucoseData(timeStamp: Date(), glucoseLevelRaw: testAmount)
        debuglogging("timestamp testdata = " + testdata.timeStamp.description + ", with amount = " + testAmount.description)
        var testdataasarray = [testdata]
        cgmTransmitterDelegate?.cgmTransmitterInfoReceived(glucoseData: &testdataasarray, transmitterBatteryInfo: nil, sensorTimeInMinutes: nil)
        testAmount = testAmount + 1
    }
    
    // MARK: public functions
    
    /// scale the rawValue, dependent on transmitter version G5 , G6 --
    /// for G6, there's two possible scaling factors, depending on the firmware version. For G5 there's only one, firmware version independent
    /// - parameters:
    ///     - firmwareVersion : for G6, the scaling factor is firmware dependent. Parameter created optional although it is known at the moment the function is used
    ///     - the value to be scaled
    /// this function can be override in CGMG6Transmitter, which can then return the scalingFactor , firmware dependent
    func scaleRawValue(firmwareVersion: String?, rawValue: Double) -> Double {
        
        // for G5, the scaling is independent of the firmwareVersion
        // and there's no scaling to do
        return rawValue
        
    }
    
    // MARK: - deinit

    deinit {
        
        // if deinit is called, it means user deletes the transmitter or clicks 'stop scanning' or 'disconnect'.  TimeStampOfLastBatteryReading must be set to nil to make sure if new transmitter is added, battery read is done again
        UserDefaults.standard.timeStampOfLastBatteryReading = nil
        
    }

    // MARK: - BluetoothTransmitter overriden functions

    override func initiatePairing() {
        // assuming that the transmitter is effectively awaiting the pairing, otherwise this obviously won't work
        sendPairingRequest()
    }

    override func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        
        super.centralManager(central, didDisconnectPeripheral: peripheral, error: error)
        
        if waitingPairingConfirmation {
            // device has requested a pairing request and is now in a status of verifying if pairing was successfull or not, this by doing setNotify to writeCharacteristic. If a disconnect occurs now, it means pairing has failed (probably because user didn't approve it
            waitingPairingConfirmation = false
            
            // inform delegate
            bluetoothTransmitterDelegate?.pairingFailed()
            
        }
        
        // setting characteristics to nil, they will be reinitialized at next connect
        writeControlCharacteristic = nil
        receiveAuthenticationCharacteristic = nil
        communicationCharacteristic = nil
        backfillCharacteristic = nil
        
    }

    override func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        
        super.peripheral(peripheral, didUpdateNotificationStateFor: characteristic, error: error)
        
        trace("in peripheralDidUpdateNotificationStateFor", log: log, category: ConstantsLog.categoryCGMG5, type: .info)
        
        if let error = error {
            trace("    error: %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .error , error.localizedDescription)
        }
        
        if let characteristicValue = CBUUID_Characteristic_UUID(rawValue: characteristic.uuid.uuidString) {
            
            trace("    characteristic : %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info, characteristicValue.description)
            
            switch characteristicValue {
                
            case .CBUUID_Receive_Authentication:

                sendAuthRequestTxMessage()
                
                break

            default:
                if (G5ResetRequested) {
                    // send ResetTxMessage
                    sendG5Reset()
                    
                    //reset G5ResetRequested to false
                    G5ResetRequested = false
                    
                } else {

                    // is it a firefly ?
                    // if no treat it as a G5, with own calibration
                    if !isFireFly() {
                        
                        // send SensorTxMessage to transmitter
                        getSensorData()
                        
                        return
                        
                    }
                    
                    // it a transmitter with transmitterid >= 8G
                    // continue with the firefly message flow
                    fireflyMessageFlow()
                    
                }
                
                break
                
            }
        } else {
            trace("    characteristicValue is nil", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
        }
        
    }
    
    override func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        
        super.peripheral(peripheral, didUpdateValueFor: characteristic, error: error)
        
        guard let characteristic_UUID = CBUUID_Characteristic_UUID(rawValue: characteristic.uuid.uuidString) else {
            trace("in peripheralDidUpdateValueFor, unknown characteristic received with uuid = %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .error, characteristic.uuid.uuidString)
            return
        }
        
        trace("in peripheralDidUpdateValueFor, characteristic uuid = %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info, characteristic_UUID.description)
        
        if let error = error {
            trace("error: %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .error , error.localizedDescription)
        }
        
        switch characteristic_UUID {

        case .CBUUID_Backfill:
            
            // transmitterDate should be non nil
            guard let transmitterStartDate = transmitterStartDate else {
                
                trace("    started processing backfillstream but transmitterStartDate is nil, no further processing", log: log, category: ConstantsLog.categoryCGMG5, type: .info)
                
                return
                
            }
            
            // unwrap characteristic value
            guard let value = characteristic.value else {return}
            
            // push value to backFillStream
            backFillStream.push(value)

            // initialize glucoseDataArray, this array will contain the glucose values in the stream
            var glucoseDataArray = [GlucoseData]()
            
            // iterate through backsie's
            for backsie in backFillStream.decode() {
                
                let backsieDate = transmitterStartDate + Double(backsie.dexTime)
                
                let diff = Date().timeIntervalSince1970 - backsieDate.timeIntervalSince1970
                
                guard diff > 0, diff < TimeInterval.hours(6) else { continue }
                
                glucoseDataArray.append(GlucoseData(timeStamp: backsieDate, glucoseLevelRaw: Double(backsie.glucose)))
                
            }

            cgmTransmitterDelegate?.cgmTransmitterInfoReceived(glucoseData: &glucoseDataArray, transmitterBatteryInfo: nil, sensorTimeInMinutes: nil)
            
        default:
            
            if let value = characteristic.value {
                
                //check type of message and process according to type
                if let firstByte = value.first {
                    if let opCode = DexcomTransmitterOpCode(rawValue: firstByte) {
                        trace("    opcode = %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info, opCode.description)
                        switch opCode {
                            
                        case .authChallengeRx:
                            if let authChallengeRxMessage = AuthChallengeRxMessage(data: value) {
                                
                                // if not paired, then send message to delegate
                                if !authChallengeRxMessage.paired {
                                    
                                    trace("    transmitter needs pairing, calling sendKeepAliveMessage", log: log, category: ConstantsLog.categoryCGMG5, type: .info)
                                    
                                    // will send keep alive message
                                    sendKeepAliveMessage()
                                    
                                    // delegate needs to be informed that pairing is needed
                                    bluetoothTransmitterDelegate?.transmitterNeedsPairing(bluetoothTransmitter: self)
                                    
                                } else {
                                    
                                    // subscribe to writeControlCharacteristic
                                    if let writeControlCharacteristic = writeControlCharacteristic {
                                        setNotifyValue(true, for: writeControlCharacteristic)
                                    } else {
                                        trace("    writeControlCharacteristic is nil, can not set notifyValue", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
                                    }
                                    
                                    // subscribe to backfillCharacteristic
                                    if let backfillCharacteristic = backfillCharacteristic {
                                        
                                        setNotifyValue(true, for: backfillCharacteristic)
                                        
                                    } else {
                                        
                                        trace("    backfillCharacteristic is nil, can not set notifyValue", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
                                        
                                    }
                                    
                                }
                                
                            } else {
                                trace("    failed to create authChallengeRxMessage", log: log, category: ConstantsLog.categoryCGMG5, type: .info)
                            }
                            
                        case .authRequestRx:
                            if let authRequestRxMessage = AuthRequestRxMessage(data: value), let receiveAuthenticationCharacteristic = receiveAuthenticationCharacteristic {
                                
                                guard let challengeHash = CGMG5Transmitter.computeHash(transmitterId, of: authRequestRxMessage.challenge) else {
                                    trace("    failed to calculate challengeHash, no further processing", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
                                    return
                                }
                                
                                let authChallengeTxMessage = AuthChallengeTxMessage(challengeHash: challengeHash)
                                
                                trace("sending authChallengeTxMessage with data %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info, authChallengeTxMessage.data.hexEncodedString())
                                
                                _ = writeDataToPeripheral(data: authChallengeTxMessage.data, characteristicToWriteTo: receiveAuthenticationCharacteristic, type: .withResponse)
                                
                            } else {
                                trace("    writeControlCharacteristic is nil or authRequestRxMessage is nil", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
                            }
                            
                        case .sensorDataRx:
                            
                            // if this is the first sensorDataRx after a successful pairing, then inform delegate that pairing is finished
                            if waitingPairingConfirmation {
                                waitingPairingConfirmation = false
                                bluetoothTransmitterDelegate?.successfullyPaired()
                            }
                            
                            if let sensorDataRxMessage = SensorDataRxMessage(data: value) {
                                
                                // should we request firmware or battery level
                                if !requestFirmware {
                                    
                                    // request battery level now, next time request firmware
                                    requestFirmware = true
                                    
                                    // transmitterversion was already received, let's see if we need to get the batterystatus
                                    // and if not, then disconnect
                                    if !batteryStatusRequested() {
                                        
                                        disconnect()
                                        
                                    }
                                    
                                } else {
                                    
                                    // request firmware now, next time request battery level
                                    requestFirmware = false
                                    
                                    if firmware == nil {
                                        
                                        sendTransmitterVersionTxMessage()
                                        
                                    }
                                }
                                
                                //if reset was done recently, less than 5 minutes ago, then ignore the reading
                                if Date() < Date(timeInterval: 5 * 60, since: timeStampTransmitterReset) {
                                    trace("    last transmitter reset was less than 5 minutes ago, ignoring this reading", log: log, category: ConstantsLog.categoryCGMG5, type: .info)
                                    //} else if sensorDataRxMessage.unfiltered == 0.0 {
                                    //  trace("    sensorDataRxMessage.unfiltered = 0.0, ignoring this reading", log: log, category: ConstantsLog.categoryCGMG5, type: .info)
                                } else {
                                    if Date() < Date(timeInterval: 60, since: timeStampOfLastG5Reading) {
                                        
                                        // should probably never come here because this check is already done at connection time
                                        trace("    last reading was less than 1 minute ago, ignoring", log: log, category: ConstantsLog.categoryCGMG5, type: .info)
                                        
                                    } else {
                                        
                                        // check if rawValue equals 2096896, this indicates low battery, error message needs to be shown in that case
                                        if sensorDataRxMessage.unfiltered == 2096896.0 {
                                            
                                            trace("    received unfiltered value 2096896.0, which is caused by low battery. Creating error message", log: log, category: ConstantsLog.categoryCGMG5, type: .info)
                                            
                                            cgmTransmitterDelegate?.errorOccurred(xDripError: DexcomError.receivedEnfilteredValue2096896)
                                            
                                        } else {
                                            
                                            timeStampOfLastG5Reading = Date()
                                            
                                            let glucoseData = GlucoseData(timeStamp: sensorDataRxMessage.timestamp, glucoseLevelRaw: scaleRawValue(firmwareVersion: firmware, rawValue: sensorDataRxMessage.unfiltered))
                                            
                                            var glucoseDataArray = [glucoseData]
                                            
                                            cgmTransmitterDelegate?.cgmTransmitterInfoReceived(glucoseData: &glucoseDataArray, transmitterBatteryInfo: nil, sensorTimeInMinutes: nil)
                                            
                                        }
                                        
                                        
                                    }
                                }
                                
                            } else {
                                trace("    sensorDataRxMessagee is nil", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
                            }
                            
                        case .resetRx:
                            
                            processResetRxMessage(value: value)
                            
                        case .batteryStatusRx:
                            
                            processBatteryStatusRxMessage(value: value)
                            
                            // if firefly continue with the firefly message flow
                            if isFireFly() { fireflyMessageFlow() }
                            
                        case .transmitterVersionRx:
                            
                            processTransmitterVersionRxMessage(value: value)

                            // if firefly continue with the firefly message flow
                            if isFireFly() { fireflyMessageFlow() }

                        case .keepAliveRx:
                            
                            // seems no processing is necessary, now the user should get a pairing requeset
                            break
                            
                        case .pairRequestRx:
                            
                            // don't know if the user accepted the pairing request or not, we can only know by trying to subscribe to writeControlCharacteristic - if the device is paired, we'll receive a sensorDataRx message, if not paired, then a disconnect will happen
                            
                            // set status to waitingForPairingConfirmation
                            waitingPairingConfirmation = true
                            
                            // setNotifyValue
                            if let writeControlCharacteristic = writeControlCharacteristic {
                                setNotifyValue(true, for: writeControlCharacteristic)
                            } else {
                                trace("    writeControlCharacteristic is nil, can not set notifyValue", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
                            }
                            
                        case .transmitterTimeRx:
                            
                            processTransmitterTimeRxMessage(value: value)
                            
                            // if firefly continue with the firefly message flow
                            if isFireFly() { fireflyMessageFlow() }
                            
                        case .glucoseBackfillRx:
                            
                            processGlucoseBackfillRxMessage(value: value)
                            
                        case .glucoseRx:
                            
                            processGlucoseDataRxMessage(value: value)
                            
                        case .calibrateGlucoseRx:
                            
                            processCalibrateGlucoseRxMessage(value: value)
                            
                        case .sessionStopRx:
                            
                            processSessionStopRxMessage(value: value)
                            
                        default:
                            trace("    unknown opcode received ", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
                            break
                        }
                    } else {
                        trace("    value doesn't start with a known opcode = %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .error, firstByte)
                    }
                } else {
                    trace("    characteristic.value is nil", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
                }
            }
            
            break
            
        }
        
        
    }
    
    override func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        if Date() < Date(timeInterval: 60, since: timeStampOfLastG5Reading) {
            // will probably never come here because reconnect doesn't happen with scanning, hence diddiscover will never be called excep the very first time that an app tries to connect to a G5
            trace("diddiscover peripheral, but last reading was less than 1 minute ago, will ignore", log: log, category: ConstantsLog.categoryCGMG5, type: .info)
        } else {
            super.centralManager(central, didDiscover: peripheral, advertisementData: advertisementData, rssi: RSSI)
        }
        
    }

    override func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        // not calling super.didconnect here
        
        // if last reading was less than a minute ago, then no need to continue, otherwise continue with process by calling super.centralManager(central, didConnect: peripheral)
        if Date() < Date(timeInterval: 60, since: timeStampOfLastG5Reading) {
            trace("connected, but last reading was less than 1 minute ago", log: log, category: ConstantsLog.categoryCGMG5, type: .info)
            // don't disconnect here, keep the connection open, the transmitter will disconnect in a few seconds, assumption is that this will increase battery life
        } else {
            super.centralManager(central, didConnect: peripheral)
        }
        
        // to be sure waitingPairingConfirmation is reset to false
        waitingPairingConfirmation = false
        
    }
    
    override func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        // not using super.didDiscoverCharacteristicsFor here
        
        trace("didDiscoverCharacteristicsFor", log: log, category: ConstantsLog.categoryCGMG5, type: .info)
        
        // log error if any
        if let error = error {
            trace("    error: %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .error , error.localizedDescription)
        }
        
        if let characteristics = service.characteristics {
            
            for characteristic in characteristics {
                
                if let characteristicValue = CBUUID_Characteristic_UUID(rawValue: characteristic.uuid.uuidString) {

                    trace("    characteristic : %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info, characteristicValue.description)
                    
                    switch characteristicValue {
                    case .CBUUID_Backfill:
                        backfillCharacteristic = characteristic
                        
                    case .CBUUID_Write_Control:
                        writeControlCharacteristic = characteristic
                        
                    case .CBUUID_Communication:
                        communicationCharacteristic = characteristic
                        
                    case .CBUUID_Receive_Authentication:
                        
                        receiveAuthenticationCharacteristic = characteristic
                        
                        trace("    calling setNotifyValue true for characteristic %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info, CBUUID_Characteristic_UUID.CBUUID_Receive_Authentication.description)
                        
                        peripheral.setNotifyValue(true, for: characteristic)
                        
                    }
                } else {
                    trace("    characteristic UUID unknown : %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .error, characteristic.uuid.uuidString)
                }
            }
        } else {
            trace("characteristics is nil. There must be some error.", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
        }
    }
    
    // MARK: CGMTransmitter protocol functions
    
    /// to ask transmitter reset
    func reset(requested:Bool) {
        G5ResetRequested = requested
    }

    /// this transmitter does not support Libre non fixed slopes
    func setNonFixedSlopeEnabled(enabled: Bool) {    
    }

    /// this transmitter does not support oopWeb
    func setWebOOPEnabled(enabled: Bool) {
    }
    
    func cgmTransmitterType() -> CGMTransmitterType {
        return .dexcomG5
    }

    func isNonFixedSlopeEnabled() -> Bool {
        return false
    }
    
    func isWebOOPEnabled() -> Bool {
        return false
    }
    
    func requestNewReading() {
        // not supported for Dexcom G5
    }
    
    func maxSensorAgeInDays() -> Int? {
        
        // no max sensor age for Dexcom
        return nil
        
    }

    
    // MARK: helper functions
    
    /// sends SensorTxMessage to transmitter
    private func getSensorData() {
        
        trace("trying to send SensorDataTxMessage", log: log, category: ConstantsLog.categoryCGMG5, type: .info)
        
        if let writeControlCharacteristic = writeControlCharacteristic {
            
            _ = writeDataToPeripheral(data: SensorDataTxMessage().data, characteristicToWriteTo: writeControlCharacteristic, type: .withResponse)
            
        } else {
            
            trace("    writeControlCharacteristic is nil, not sending SensorDataTxMessage", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
            
        }
    }
    
    
    /// sends G5 reset to transmitter
    private func sendG5Reset() {
        trace("in sendG5Reset", log: log, category: ConstantsLog.categoryCGMG5, type: .info)
        if let writeControlCharacteristic = writeControlCharacteristic {
            _ = writeDataToPeripheral(data: ResetTxMessage().data, characteristicToWriteTo: writeControlCharacteristic, type: .withResponse)
            G5ResetRequested = false
        } else {
            trace("    writeControlCharacteristic is nil, not sending G5 reset", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
        }
    }
    
    /// sends transmitterTimeTxMessage to transmitter
    private func sendTransmitterTimeTxMessage() {
        
        if let writeControlCharacteristic = writeControlCharacteristic {
            
            _ = writeDataToPeripheral(data: DexcomTransmitterTimeTxMessage().data, characteristicToWriteTo: writeControlCharacteristic, type: .withResponse)
            
        } else {
            
            trace("writeControlCharacteristic is nil", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
            
        }
        
    }

    /// sends AuthRequestTxMessage to transmitter
    private func sendAuthRequestTxMessage() {
        
        let authMessage = AuthRequestTxMessage()
        
        if let receiveAuthenticationCharacteristic = receiveAuthenticationCharacteristic {

            trace("sending authMessage with data %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info, authMessage.data.hexEncodedString())

            _ = writeDataToPeripheral(data: authMessage.data, characteristicToWriteTo: receiveAuthenticationCharacteristic, type: .withResponse)
            
        } else {
            
            trace("receiveAuthenticationCharacteristic is nil", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
            
        }
    }
    
    private func sendTransmitterVersionTxMessage() {
        
        if let writeControlCharacteristic = writeControlCharacteristic {
            _ = writeDataToPeripheral(data: TransmitterVersionTxMessage().data, characteristicToWriteTo: writeControlCharacteristic, type: .withResponse)
            
        } else {
            
            trace("    writeControlCharacteristic is nil, can not send TransmitterVersionTxMessage", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
            
        }

    }
    
    private func processResetRxMessage(value:Data) {
        
        if let resetRxMessage = ResetRxMessage(data: value) {

            trace("in processResetRxMessage, considering reset successful = %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info, (resetRxMessage.status == 0).description)

            cGMG5TransmitterDelegate?.reset(for: self, successful: resetRxMessage.status == 0 )
            
        } else {
            
            trace("resetRxMessage is nil", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
            
        }
        
    }
    
    /// process batteryStatusRxMessage
    private func processBatteryStatusRxMessage(value:Data) {
        
        if let batteryStatusRxMessage = BatteryStatusRxMessage(data: value) {

            trace("in processBatteryStatusRxMessage, voltageA = %{public}@, voltageB = %{public}@, resist = %{public}@, runtime = %{public}@, temperature = %{public}@, status = %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info, batteryStatusRxMessage.voltageA.description, batteryStatusRxMessage.voltageB.description, batteryStatusRxMessage.resist.description, batteryStatusRxMessage.runtime.description, batteryStatusRxMessage.temperature.description, batteryStatusRxMessage.status.description)

            // cGMG5TransmitterDelegate for showing info on bluetoothviewcontroller and store in coredata
            cGMG5TransmitterDelegate?.received(transmitterBatteryInfo: TransmitterBatteryInfo.DexcomG5(voltageA: batteryStatusRxMessage.voltageA, voltageB: batteryStatusRxMessage.voltageB, resist: batteryStatusRxMessage.resist, runtime: batteryStatusRxMessage.runtime, temperature: batteryStatusRxMessage.temperature), cGMG5Transmitter: self)
            
            // cgmTransmitterDelegate , because rootviewcontroller also shows battery info in home screen
            cgmTransmitterDelegate?.cgmTransmitterInfoReceived(glucoseData: &emptyArray, transmitterBatteryInfo: TransmitterBatteryInfo.DexcomG5(voltageA: batteryStatusRxMessage.voltageA, voltageB: batteryStatusRxMessage.voltageB, resist: batteryStatusRxMessage.resist, runtime: batteryStatusRxMessage.runtime, temperature: batteryStatusRxMessage.temperature), sensorTimeInMinutes: nil)
            
        } else {
            
            trace("batteryStatusRxMessage is nil", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
            
        }
        
    }

    /// process glucoseBackfillRxMessage
    private func processGlucoseBackfillRxMessage(value:Data) {
        
        if let glucoseBackFillRxMessage = GlucoseBackfillRxMessage(data: value) {
            
            trace("backFillRxMessage not yet processed, value = %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info, value.hexEncodedString())
            
        } else {
            trace("backFillRxMessage is nil", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
        }
        
    }
    
    /// process sessionStopRxMessage
    private func processSessionStopRxMessage(value: Data) {
        
        if let dexcomSessionStopRxMessage = DexcomSessionStopRxMessage(data: value) {
            
            trace("in processSessionStopRxMessage, received dexcomSessionStopRxMessage, isOkay = %{public}@, received = %{public}@, sessionStartTime = %{public}@, sessionStopTime = %{public}@, status = %{public}@, transmitterTime = %{public}@,", log: log, category: ConstantsLog.categoryCGMG5, type: .info, dexcomSessionStopRxMessage.isOkay.description, dexcomSessionStopRxMessage.received.description, dexcomSessionStopRxMessage.sessionStartTime.description, dexcomSessionStopRxMessage.sessionStopTime.description, dexcomSessionStopRxMessage.status.description, dexcomSessionStopRxMessage.transmitterTime.description)
            
        } else {
            trace("dexcomSessionStopRxMessage is nil", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
        }
        
    }
    
    /// processSessionStartRxMessage
    private func processSessionStartRxMessage(value: Data) {
        
        if let dexcomSessionStartRxMessage = DexcomSessionStartRxMessage(data: value) {
            
            trace("in processSessionStartRxMessage, received dexcomSessionStartRxMessage, info = %{public}@, requestedStartTime = %{public}@, sessionStartTime = %{public}@, status = %{public}@, transmitterTime = %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info,
                  dexcomSessionStartRxMessage.info.description,
                  dexcomSessionStartRxMessage.requestedStartTime.description,
                  dexcomSessionStartRxMessage.sessionStartTime.description,
                  dexcomSessionStartRxMessage.status.description,
                  dexcomSessionStartRxMessage.transmitterTime.description)
            
        } else {
            trace("dexcomSessionStartRxMessage is nil", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
        }
        
    }
    
    /// process CalibrateGlucoseRxMessage
    private func processCalibrateGlucoseRxMessage(value: Data) {
        
        if let dexcomCalibrationRxMessage = DexcomCalibrationRxMessage(data: value) {
            
            var type = "unknown"
            
            if let dexcomCalibrationResponseType = dexcomCalibrationRxMessage.type {
                type = dexcomCalibrationResponseType.description
            }
            
            trace("in processCalibrateGlucoseRxMessage, received dexcomCalibrationRxMessage, accepted = %{public}@, type = %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info, dexcomCalibrationRxMessage.accepted.description, type)
            
        } else {
            trace("dexcomCalibrationRxMessage is nil", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
        }
        
    }
    
    /// process glucoseRxMessage
    private func processGlucoseDataRxMessage(value: Data) {
        
        if let glucoseDataRxMessage = GlucoseDataRxMessage(data: value) {
            
            trace("in processGlucoseDataRxMessage, received glucoseDataRxMessage, value = %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info, glucoseDataRxMessage.calculatedValue.description)
            
        } else {
            trace("glucoseDataRxMessage is nil", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
        }
        
    }
    
    /// process transmitterTimeRxMessage
    private func processTransmitterTimeRxMessage(value:Data) {
        
        if let transmitterTimeRxMessage = DexcomTransmitterTimeRxMessage(data: value) {
            
            // assign transmittertime
            transmitterStartDate = transmitterTimeRxMessage.transmitterStartDate
            
            trace("in  processTransmitterTimeRxMessage, transmitterStartDate = %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info, transmitterStartDate!.toString(timeStyle: .long, dateStyle: .long))
            
            if let transmitterStartDate = transmitterStartDate {
                
                // send to delegate
                cGMG5TransmitterDelegate?.received(transmitterStartDate: transmitterStartDate, cGMG5Transmitter: self)

            } else {
                trace("transmitterStartDate is nil", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
            }
            
        } else {
            trace("transmitterTimeRxMessage is nil", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
        }
        
    }

    private func processTransmitterVersionRxMessage(value:Data) {
        
        if let transmitterVersionRxMessage = TransmitterVersionRxMessage(data: value) {
            
            // assign transmitterVersion
            firmware = transmitterVersionRxMessage.firmwareVersionFormatted()
            
            trace("in  processTransmitterVersionRxMessage, firmware = %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info, firmware!)

            // send to delegate
            cGMG5TransmitterDelegate?.received(firmware: firmware!, cGMG5Transmitter: self)
            
        } else {
            trace("transmitterVersionRxMessage is nil or firmware to hex is  nil", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
        }
        
    }

    /// calculates encryptionkey
    private static func cryptKey(_ id:String) -> Data? {
        return "00\(id)00\(id)".data(using: .utf8)
    }
    
    /// compute hash
    private static func computeHash(_ id:String, of data: Data) -> Data? {
        guard data.count == 8 else {
            return nil
        }
        
        var doubleData = Data(capacity: data.count * 2)
        doubleData.append(data)
        doubleData.append(data)
        
        if let cryptKey = cryptKey(id) {
            if let outData = try? AESCrypt.encryptData(doubleData, usingKey: cryptKey) {
                return outData[0..<8]
            }
        }
        return nil
    }

    /// sends pairing request to transmitter, this will result in an iOS generated pairing request
    private func sendPairingRequest() {
        
        if let receiveAuthenticationCharacteristic = receiveAuthenticationCharacteristic {
            
            _ = writeDataToPeripheral(data: PairRequestTxMessage().data, characteristicToWriteTo: receiveAuthenticationCharacteristic, type: .withResponse)

        } else {
            trace("    in sendBondingRequest, receiveAuthenticationCharacteristic is nil, can not send KeepAliveTxMessage", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
        }

    }

    /// sends a keepalive message, this will keep the connection with the transmitter open for 60 seconds
    private func sendKeepAliveMessage() {

        if let receiveAuthenticationCharacteristic = receiveAuthenticationCharacteristic {
            
            // to make sure the Dexcom doesn't disconnect the next 60 seconds, this gives the user sufficient time to accept the pairing request, which will come next
            _ = writeDataToPeripheral(data: KeepAliveTxMessage(time: UInt8(ConstantsDexcomG5.maxTimeToAcceptPairingInSeconds)).data, characteristicToWriteTo: receiveAuthenticationCharacteristic, type: .withResponse)
            
        } else {
            trace("    in sendKeepAliveMessage, receiveAuthenticationCharacteristic is nil, can not send KeepAliveTxMessage", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
        }

    }
    
    /// - checks if battery status needs to be requested to tranmsitter (depends on when it was last updated), and if yes requests it (ie sends message BatteryStatusTxMessage)
    /// - returns:
    ///     - true if batter status requested, otherwise false
    private func batteryStatusRequested() -> Bool {
        
        if Date() > Date(timeInterval: ConstantsDexcomG5.batteryReadPeriodInHours * 60 * 60, since: UserDefaults.standard.timeStampOfLastBatteryReading != nil ? UserDefaults.standard.timeStampOfLastBatteryReading! : Date(timeIntervalSince1970: 0)) {
            trace("    last battery reading was long time ago, requesting now", log: log, category: ConstantsLog.categoryCGMG5, type: .info)
            if let writeControlCharacteristic = writeControlCharacteristic {
                _ = writeDataToPeripheral(data: BatteryStatusTxMessage().data, characteristicToWriteTo: writeControlCharacteristic, type: .withResponse)

                return true
                
            } else {
                
                trace("    writeControlCharacteristic is nil, can not send BatteryStatusTxMessage", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
                
                return false
                
            }
            
        } else {
            
            return false
            
        }
        
    }
    
    /// verifies if it's a firefly based on transmitterId, if >= 8G then considered to be a Firefly
    private func isFireFly() -> Bool {
        
        return transmitterId.uppercased().compare("8G") == .orderedDescending
        
    }
    
    /// - if firefly then calls setNotifyValue(true) for both writeControlCharacteristic and backfillCharacteristic
    /// - if not firefly then only calls setNotifyValue(true) for both writeControlCharacteristic
    private func subscribeToWriteControlAndBackFillCharacteristic() {
        
        // subscribe to writeControlCharacteristic
        if let writeControlCharacteristic = writeControlCharacteristic {
            
            trace("    calling setNotifyValue true for characteristic %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info, CBUUID_Characteristic_UUID.CBUUID_Write_Control.description)
            
            setNotifyValue(true, for: writeControlCharacteristic)
            
        } else {
            
            trace("    writeControlCharacteristic is nil, can not set notifyValue", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
            
        }
        
        // if firefly, then subscribe to backfillCharacteristic
        if isFireFly(), let backfillCharacteristic = backfillCharacteristic {
            
            trace("    calling setNotifyValue true for characteristic %{public}@", log: log, category: ConstantsLog.categoryCGMG5, type: .info, CBUUID_Characteristic_UUID.CBUUID_Backfill.description)
            
            setNotifyValue(true, for: backfillCharacteristic)
            
        } else {
            
            trace("    backfillCharacteristic is nil, can not set notifyValue", log: log, category: ConstantsLog.categoryCGMG5, type: .error)
            
        }
        
    }
    
    /// - verifies what is the next message to send to the firefly (is it battery request, firmware request, etc...
    /// - and sends that message
    private func fireflyMessageFlow() {
        
        // first of all check that the transmitter is really a firefly, if not stop processing
        if !isFireFly() { return }
        
        // treat it as a firefly, ie using the calibration on the sensor
        guard firmware != nil else {
            
            sendTransmitterVersionTxMessage()
            
            return
            
        }
        
        // check if battery status update needed
        if !batteryStatusRequested() {
            
            if transmitterStartDate != nil {
                
                let t = 1
                
            } else {
                
                // request transmitterStartDate
                sendTransmitterTimeTxMessage()
                
            }
            
        }
        
    }
    
}

#include <Wire.h>
#include <Adafruit_MCP23017.h>
#include <Adafruit_RGBLCDShield.h>

#include <SdFat.h>
#include <SdFatUtil.h>
//#include <SPI.h>

Adafruit_RGBLCDShield lcd = Adafruit_RGBLCDShield();

// These #defines make it easy to set the backlight color
#define RED 0x1
#define YELLOW 0x3
#define GREEN 0x2
#define TEAL 0x6
#define BLUE 0x4
#define VIOLET 0x5
#define WHITE 0x7

#define HEADER_CHUNK_ID 0x4D546864  // MThd
#define TRACK_CHUNK_ID 0x4D54726B   // MTrk
#define SD_BUFFER_SIZE 512
#define DELTA_TIME_VALUE_MASK 0x7F
#define DELTA_TIME_END_MASK 0x80
#define DELTA_TIME_END_VALUE 0x80
#define EVENT_TYPE_MASK 0xF0
#define EVENT_CHANNEL_MASK 0x0F
#define NOTE_OFF_EVENT_TYPE 0x80
#define NOTE_ON_EVENT_TYPE 0x90
#define KEY_AFTERTOUCH_EVENT_TYPE 0xA0
#define CONTROL_CHANGE_EVENT_TYPE 0xB0
#define PROGRAM_CHANGE_EVENT_TYPE 0xC0
#define CHANNEL_AFTERTOUCH_EVENT_TYPE 0xD0
#define PITCH_WHEEL_CHANGE_EVENT_TYPE 0xE0
#define META_EVENT_TYPE 0xFF
#define SYSTEM_EVENT_TYPE 0xF0
#define META_SEQ_COMMAND 0x00
#define META_TEXT_COMMAND 0x01
#define META_COPYRIGHT_COMMAND 0x02
#define META_TRACK_NAME_COMMAND 0x03
#define META_INST_NAME_COMMAND 0x04
#define META_LYRICS_COMMAND 0x05
#define META_MARKER_COMMAND 0x06
#define META_CUE_POINT_COMMAND 0x07
#define META_CHANNEL_PREFIX_COMMAND 0x20
#define META_END_OF_TRACK_COMMAND 0x2F
#define META_SET_TEMPO_COMMAND 0x51
#define META_SMPTE_OFFSET_COMMAND 0x54
#define META_TIME_SIG_COMMAND 0x58
#define META_KEY_SIG_COMMAND 0x59
#define META_SEQ_SPECIFIC_COMMAND 0x7F

boolean get = false;
boolean post = false;
boolean boundary = false;

boolean file_opened = false;
boolean last_block = false;
boolean file_closed = false;
boolean logging = true;
char currentSong[15];
uint16_t bufsiz=SD_BUFFER_SIZE;
uint8_t buf1[SD_BUFFER_SIZE];
uint16_t bytesread1;
uint16_t bufIndex;
uint8_t currentByte;
uint8_t previousByte;

int format;
int trackCount;
int timeDivision;

unsigned long deltaTime;
int eventType;
int eventChannel;
int parameter1;
int parameter2;

// The number of microseconds per quarter note (i.e. the current tempo)
long microseconds = 500000;
long tempoModifier = 100000;
int tempoIncrement = 0;
int tempoIncrementMax = 5;
int tempoIncrementMin = -5;
int index = 0;
unsigned long accDelta = 0;

boolean firstNote = true;
int currFreq = -1;
unsigned long lastMillis;

//int notePins[] = {21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107,108};
int notePins[] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5}; 
int pinCount = 109;
unsigned long lastDebounceTime = 1;
int debounceDelay = 150;
int lcdResetTime = 5000;
int totalCurrentNotesOn = 0;
String displayState = "";

int currentSongNum = 1;
int songNumMax = 33;
int songNumMin = 1;
boolean newSong = false;

const size_t MAX_FILE_COUNT = 500;
const char* FILE_EXT = "MID";
size_t fileCount = 0;
uint16_t fileIndex[MAX_FILE_COUNT];
String songnames[500];

boolean debugSong = false;

/************ SDCARD STUFF ************/
Sd2Card card;
SdVolume volume;
SdFile root;
SdFile file;

// store error strings in flash to save RAM
#define error(s) error_P(PSTR(s))

void error_P(const char* str) {
 PgmPrint("error: ");
 SerialPrintln_P(str);
 if (card.errorCode()) {
   PgmPrint("SD error: ");
   Serial.print(card.errorCode(), HEX);
   Serial.print(',');
   Serial.println(card.errorData(), HEX);
 }
 while(1);
}
/************ SDCARD STUFF ************/


void setup() 
{

   lcd.begin(16, 2);
   lcdDisplayDefault();
  
    if (debugSong)
   {
     Serial.begin(9600);
   }
   else
   {
     //Serial.begin(31250);
     Serial.begin(28800);
   }
   
   initNotePins();
   
   // initialize the SD card at SPI_HALF_SPEED to avoid bus errors with
   // breadboards.  use SPI_FULL_SPEED for better performance.
   pinMode(10, OUTPUT);                       // set the SS pin as an output (necessary!)
   digitalWrite(10, HIGH);                    // but turn off the W5100 chip!
   if (!card.init(SPI_FULL_SPEED, 8)) error("card.init failed!");    // speed, ChipSelectPin
   // initialize a FAT volume
   if (!volume.init(card)) error("vol.init failed!");
   //PgmPrint("Volume is FAT");
   //Serial.println(volume.fatType(),DEC);
   //Serial.println();
   if (!root.openRoot(volume)) error("openRoot failed");
    
   //InitFilenames(); 
    
   SendAllNotesOff();
}

void beginPlayback()
{
   /*
   currentSong[2] = currentSongNum%10 + '0';
   currentSongNum = currentSongNum / 10;
   currentSong[1] = currentSongNum%10 + '0';
   currentSongNum = currentSongNum / 10;
   currentSong[0] = currentSongNum%10 + '0';
   currentSong[3] = '.';
   currentSong[4] = 'M';
   currentSong[5] = 'I';
   currentSong[6] = 'D';
   currentSong[7] = '\0';
   */
   
   if (debugSong)
   {
     Serial.print("Current Song #: ");
     Serial.println(currentSong);
   }
   
   lcdDisplayDefaultPlaying();
   
   //Phase processing
   while (!file_closed)
   {
      processChunk(); // header chunk
      
      if(getFileFormat() == 0) {
        logs("MIDI file format = 0");
        int trackCount = getTrackCount();
        logi("Track Count=",trackCount);
        
        /*
        if (debugSong)
        {
          file_closed = true;
          for (int i=0; i<512; i++)
          {
            int b=buf1[i];
            Serial.print(b,HEX);
            Serial.print(" ");
            if (((i+1)/16)==((i+1)%16))
            {
              Serial.println();
            }
          }
        }
        else
        {
          */
          for(int i = 0; i < getTrackCount(); i++) {
            processChunk();
          }
          if (debugSong)
          {
            file_closed = true;
          }
          
          if (newSong == true)
          {
             startNewSong(); 
          }
          /*
        }   */       
      }
      else {
        logs("MIDI file not format 0.");
      }
  }
}

void SendAllNotesOff() 
{
  for (int channel = 0; channel < 16; channel++)
  {
    for (int note = 00; note < 128; note++) 
    {
      midiOutShortMsg(0x90+channel, note, 0x00);   
    }
  }
}
void midiOutShortMsg(int cmd, int pitch, int velocity) {
  Serial.print(cmd, BYTE);
  Serial.print(pitch, BYTE);
  Serial.print(velocity, BYTE);
}

void logs(char* string) {
  if(!debugSong)
    return;
  
  Serial.println(string);
}

void logi(char* label, int data) {
  if(!debugSong)
    return;
  
  Serial.print(label);
  Serial.print(": ");
  Serial.println(data);
}

void logl(char* label, long data) {
  if(!debugSong)
    return;
  
  Serial.print(label);
  Serial.print(": ");
  Serial.println(data,HEX);
}


void logDivision(boolean major) {
  if(!debugSong)
    return;
  
  if(major) {
    Serial.println("===========================");    
  }
  else {
    Serial.println("----------------------");
  }
}


int readInt()
{
  return readByte() << 8 | readByte();
}


long readLong() {
  return (long) readByte() << 24 | (long) readByte() << 16 | (long)readByte() << 8 | (long)readByte();
}


byte getLastByte()
{
  return currentByte;
}

byte readByte()
{
  ReadMidiByte();
  return currentByte;
}


void ReadMidiByte()
{
  if (!file_opened)
  {
     if (file.open(root, currentSong, O_READ)) 
     {
        logs("Opened file");
        file_opened = true;
        ReadNextBlock();
     }
  }
  previousByte = currentByte;
  currentByte = buf1[bufIndex];
  bufIndex++;
  if (bufIndex >= bytesread1)
  {
       if (last_block)
       {
          file.close();   
          file_closed = true;
          logs("\nDone");         
       }
       else
       {
           ReadNextBlock();
       }     
  }
}

void ReadNextBlock()
{
        bytesread1 = file.read(buf1,bufsiz);
        bufIndex = 0;
        if (bytesread1 < bufsiz)
        {
           logs("Last Block");
           last_block = true;
        }
        else
        {
          logi("BUF1 Bytes read",bytesread1);
        }
}

void processByte(uint8_t b)
{
  if (debugSong)
  {
    Serial.print(b,HEX);
    Serial.print(" ");
  }
}

void processChunk() {
  boolean valid = true;
  
  long chunkID = readLong();
  long size = readLong();
  
  logDivision(true);
  logi("Chunk ID", chunkID);
  logl("Chunk Size", size);
  
  if(chunkID == HEADER_CHUNK_ID) {
    processHeader(size);
    
    logi("File format", getFileFormat());
    logi("Track count", getTrackCount());
    logi("Time division", getTimeDivision());
  }
  else if(chunkID == TRACK_CHUNK_ID) {
    processTrack(size);
  }
}


/*
 * Parses useful information out of the MIDI file header.
 */
void processHeader(long size) {
  // size should always be 6
  // do we want to bother checking?
  
  format = readInt();
  trackCount = readInt();
  timeDivision = readInt();
  
  //logs("Processed header info.");
}

int getFileFormat() {
  return format;
}

int getTrackCount() {
  return trackCount;
}

int getTimeDivision() {
  return timeDivision;
}

/*
 * Loops through a track of the MIDI file, processing the data as it goes.
 */

void processTrack(long size) {
  long counter = 0;

  while(counter < size) {
    //logl("Track counter", counter);
    counter += processEvent();
    if (newSong == true)
    {
       break; 
    }
  }
  
  
}


/*
 * Reads an event type code from the currently open file, and handles it accordingly.
 */
int processEvent() {
  //logDivision(false);
  
  checkInput();
  
  int counter = 0;
  deltaTime = 0;
  
  int b;
  
  do {
    b = readByte();
    counter++;
    
    deltaTime = (deltaTime << 7) | (b & DELTA_TIME_VALUE_MASK);
  } while((b & DELTA_TIME_END_MASK) == DELTA_TIME_END_VALUE);
  
  //logi("Delta", deltaTime);
  
  b = readByte();
    counter++;

  boolean runningMode = true;
  // New events will always have a most significant bit of 1
  // Otherwise, we operate in 'running mode', whereby the last
  // event command is assumed and only the parameters follow
  if(b >= 128) {
    eventType = (b & EVENT_TYPE_MASK) >> 4;
    eventChannel = b & EVENT_CHANNEL_MASK;
    runningMode = false;
  }
  
  //logi("Event type", eventType);
  //logi("Event channel", eventChannel);
  
  // handle meta-events and track events separately
  if(eventType == (META_EVENT_TYPE & EVENT_TYPE_MASK) >> 4
     && eventChannel == (META_EVENT_TYPE & EVENT_CHANNEL_MASK)) {
    counter += processMetaEvent();
  }
  else {
    counter += processTrackEvent(runningMode, b);
  }
  
  return counter;
}

/*
 * Reads a meta-event command and size from the file, performing the appropriate action
 * for the command.
 *
 * NB: currently, only tempo changes are handled - all else is useless for our organ.
 */
int processMetaEvent() {
  int command = readByte();
  int size = readByte();
  
  //logi("Meta event length", size);
  
  for(int i = 0; i < size; i++) {
    byte data = readByte();
    
    switch(command) {
      case META_SET_TEMPO_COMMAND:
        processTempoEvent(i, data);
    }
  }
  
  return size + 2;
}

/*
 * Reads a track event from the file, either as a full event or in running mode (to
 * be determined automatically), and takes appropriate playback action.
 */
int processTrackEvent(boolean runningMode, int lastByte) {
  int count = 0;
  
  if(runningMode) {
    parameter1 = getLastByte();
  }
  else {
    parameter1 = readByte(); 
    count++;
  }
  
  //logi("Parameter 1", parameter1);
  
  int eventShift = eventType << 4;

  parameter2 = -2;  
  switch(eventShift) {
    case NOTE_OFF_EVENT_TYPE:
    case NOTE_ON_EVENT_TYPE:
    case KEY_AFTERTOUCH_EVENT_TYPE:
    case CONTROL_CHANGE_EVENT_TYPE:
    case PITCH_WHEEL_CHANGE_EVENT_TYPE:
    default:
      parameter2 = readByte();
      count++;

      //logi("Parameter 2", parameter2);
      
      break;
    case PROGRAM_CHANGE_EVENT_TYPE:
    case CHANNEL_AFTERTOUCH_EVENT_TYPE:
      parameter2 = -1;
      break;
  }
  
  if(eventShift == NOTE_OFF_EVENT_TYPE)
  {
    triggerNote("OFF", parameter1);
  }
  if(eventShift == NOTE_ON_EVENT_TYPE)
  {
    triggerNote("ON", parameter1);
  }
  
  if (parameter2 >= 0)
  {
    processMidiEvent(deltaTime, eventType*16+eventChannel, parameter1, parameter2);
  }
  else if (parameter2 == -1)
  {
    process2ByteMidiEvent(deltaTime, eventType*16+eventChannel, parameter1);
  }
  else {
    addDelta(deltaTime);
  }
  
  return count;
}


/*
 * Handles a tempo event with the given values.
 */
void processTempoEvent(int paramIndex, byte param) {
  byte bits = 16 - 8*paramIndex;
  microseconds = (microseconds & ~((long) 0xFF << bits)) | ((long) param << bits);
  //Serial.print("TEMPO:");
  //Serial.println(microseconds);
}
  
long getMicrosecondsPerQuarterNote() {
  return microseconds;
}

void addDelta(unsigned long delta) {
  accDelta = accDelta + delta;
}

void resetDelta() {
  accDelta = 0;
}

void processMidiEvent(unsigned long delta, int channel, int note, int velocity) {
  addDelta(delta);
  
  playback(channel, note, velocity, accDelta);
  index++;
  
  resetDelta();
}

void process2ByteMidiEvent(unsigned long delta, int channel, int value) {
  addDelta(delta);
  
  playback(channel, value, -1, accDelta);
  index++;
  
  resetDelta();
}


void playback(int channel, int note, int velocity, unsigned long delta) {
  unsigned long deltaMillis = (delta * getMicrosecondsPerQuarterNote()) / (((long) getTimeDivision()) * 1000);
  
  if(firstNote) {
    firstNote = false;
  }
  else {
    unsigned long currMillis = millis();
    
    if(currMillis < lastMillis + deltaMillis)
    {
      //delay(lastMillis - currMillis + deltaMillis);
        unsigned long startTime=millis();
        while(millis()<startTime+(lastMillis - currMillis + deltaMillis))
        {
           checkInput();
        }
    }
  }

  if (velocity < 0)
  {
      midi2ByteMsg (channel, note);
  }
  else
  {  
      midiShortMsg (channel, note, velocity);
  } 
  lastMillis = millis();
}

void midiShortMsg(int cmd, int pitch, int velocity) {  
  Serial.print(cmd, BYTE);
  //Serial.print(" ");
  Serial.print(pitch, BYTE);
  //Serial.print(" ");
  Serial.print(velocity, BYTE);
  //Serial.println();
}

void midi2ByteMsg(int cmd, int value) {
  Serial.print(cmd, BYTE);
  //Serial.print(" ");
  Serial.print(value, BYTE);
  //Serial.println();
}

void InitFilenames()
{
    // start at beginning of root directory
    root.rewind();
    dir_t dir;
    char name[13];
    
    // find files
    while (root.readDir(&dir) == sizeof(dir)) {
      if (strncmp((char*)&dir.name[8], FILE_EXT, 3)) continue;
      if (fileCount >= MAX_FILE_COUNT) error("Too many files");
      fileIndex[fileCount++] = root.curPosition()/sizeof(dir) - 1;
    }
    
    songNumMax = fileCount;
    
    for (size_t i = 0; i < fileCount; i++) 
    {
      if (!file.open(root, fileIndex[i], O_READ)) error("open failed");
      file.getFilename(name);
      songnames[i] = name;
      file.close();
      SdFile file;
    }
}

void triggerNote(char* cmd, int note) {
    int note2pin = notePins[note];
    if(cmd == "OFF")
    {
      totalCurrentNotesOn = totalCurrentNotesOn - 1;
      digitalWrite(note2pin, LOW);
      logs("OFF");
      logi("note: ", note);
      logi("pin: ", note2pin);
    }
    if(cmd == "ON")
    {
      totalCurrentNotesOn = totalCurrentNotesOn + 1;
      digitalWrite(note2pin, HIGH);
      logs("ON");
      logi("note: ", note);
      logi("pin: ", note2pin);
    }
    
    //lcd.setCursor(14,1);
    //lcd.print(totalCurrentNotesOn);
}

void initNotePins() {
  for (int thisPin = 0; thisPin < pinCount; thisPin++)  
  {
    pinMode(notePins[thisPin], OUTPUT);      
  }
}

void lcdDisplayDefaultPlaying()
{
   if (displayState != "playing")
   {
     displayState = "playing";
     lcd.clear();
     lcd.setBacklight(WHITE);
     lcd.setCursor(0,0);
     lcd.print("Now Playing:");
     lcd.setCursor(0,1);
     lcd.print(currentSong);
   }
}

void lcdDisplayDefault()
{
   if (displayState != "splash")
   {
     displayState = "splash";
     lcd.clear();
     lcd.setCursor(0,0);
     lcd.print(" Arduino Player ");
     lcd.setCursor(0,1);
     lcd.print("   Piano V1.0   ");
   }
}

void startNewSong()
{
    file.close();
    tempoIncrement = 0;
    index = 0;
    accDelta = 0;
    firstNote = true;
    currFreq = -1;
    get = false;
    post = false;
    boundary = false;
    file_opened = false;
    last_block = false;
    file_closed = false;
    
    newSong = false;
    SendAllNotesOff();
    beginPlayback();
}

void checkInput()
{
   uint8_t buttons = lcd.readButtons();

   if (buttons && ((millis() - lastDebounceTime) > debounceDelay)) 
   {
      lastDebounceTime = millis();
      lcd.setCursor(0,0);
      if (buttons & BUTTON_UP) 
      {
          if (tempoIncrement < tempoIncrementMax)
          {
              tempoIncrement = tempoIncrement + 1;
              microseconds = microseconds - tempoModifier;  
              if (displayState != "tempoChange")
              {
                  lcd.clear();
                  lcd.print("Tempo Change: ");
                  lcd.setCursor(0,1);
                  lcd.print(tempoIncrement);              
              }
              else
              {
                  lcd.setCursor(0,1);
                  lcd.print("                ");
                  lcd.setCursor(0,1);
                  lcd.print(tempoIncrement);
              }       
          }
          lcd.setBacklight(RED);
          displayState = "tempoChange";
      }
      if (buttons & BUTTON_DOWN) 
      {
          if (tempoIncrement > tempoIncrementMin)
          {
              tempoIncrement = tempoIncrement - 1;
              microseconds = microseconds + tempoModifier; 
              if (displayState != "tempoChange")
              {
                  lcd.clear();
                  lcd.print("Tempo Change: ");
                  lcd.setCursor(0,1);
                  lcd.print(tempoIncrement);              
              }
              else
              {
                  lcd.setCursor(0,1);
                  lcd.print("                ");
                  lcd.setCursor(0,1);
                  lcd.print(tempoIncrement);
              }        
          }
          lcd.setBacklight(YELLOW);
          displayState = "tempoChange"; 
      }
      if (buttons & BUTTON_LEFT) 
      {
          if (currentSongNum > songNumMin)
          {
              currentSongNum = currentSongNum - 1;
              if (displayState != "songChange")
              {
                  lcd.clear();
                  lcd.print("Next song #:");
                  lcd.setCursor(0,1);
                  //lcd.print(songnames[currentSongNum]);
                  lcd.print(currentSongNum);
              }
              else
              {
                  lcd.setCursor(0,1);
                  lcd.print("                ");
                  lcd.setCursor(0,1);
                  //lcd.print(songnames[currentSongNum]);
                  lcd.print(currentSongNum);
              }
          }
          lcd.setBacklight(GREEN);          
          displayState = "songChange";
      }
      if (buttons & BUTTON_RIGHT) 
      {
          if (currentSongNum < songNumMax)
          {
              currentSongNum = currentSongNum + 1;
              if (displayState != "songChange")
              {
                  lcd.clear();
                  lcd.print("Next song #:");
                  lcd.setCursor(0,1);
                  //lcd.print(songnames[currentSongNum]);
                  lcd.print(currentSongNum);
              }
              else
              {
                  lcd.setCursor(0,1);
                  lcd.print("                ");
                  lcd.setCursor(0,1);
                  //lcd.print(songnames[currentSongNum]);
                  lcd.print(currentSongNum);
              }
          }
          lcd.setBacklight(TEAL);
          displayState = "songChange";
      }
      if (buttons & BUTTON_SELECT) 
      {
          lastDebounceTime = lastDebounceTime - 5000;
          lcd.clear();
          int tempSongNum = currentSongNum;
          currentSong[2] = currentSongNum%10 + '0';
          currentSongNum = currentSongNum / 10;
          currentSong[1] = currentSongNum%10 + '0';
          currentSongNum = currentSongNum / 10;
          currentSong[0] = currentSongNum%10 + '0';
          currentSong[3] = '.';
          currentSong[4] = 'M';
          currentSong[5] = 'I';
          currentSong[6] = 'D';
          currentSong[7] = '\0';
          /*
          String tempSongName = songnames[currentSongNum];
          int songNameLen = tempSongName.length();
          tempSongName.toCharArray(currentSong, songNameLen);
          */
          lcd.print("Playing song");
          lcd.setCursor(0,1);
          lcd.print(currentSong);
          lcd.setBacklight(VIOLET);
          currentSongNum = tempSongNum;
          newSong = true;
          displayState = "buttonSELECT";
          delay(1500);
      }
   }

   if (((millis() - lastDebounceTime) > lcdResetTime) && displayState != "playing" && displayState != "splash")
   {
       lcdDisplayDefaultPlaying();
   }
}

void loop()
{
    checkInput();
    
    if (newSong == true)
    {
      startNewSong(); 
    }
    else if(displayState == "playing")
    {
      lcdDisplayDefault();
    }
}


// Thanks to PHLARX for the CP counter (https://openplanet.nl/files/79)
// Thanks to tooInfinite for the help on the Trackmania API
// Thanks to Miss for the server informations (YOINKED it from the Discord script)

enum FormattingType
{
	Fixed,
	Custom
}

bool Setting_Active = false;

[Setting category="General" name="Key" password description="If you don't have a key, click on: Scripts > Twitch Chat Bot > Authenticate"]
string Setting_Key;

string Setting_Username = '';

[Setting category="General" name="Formatting" description="Fixed: Pre-formatted strings. Custom: Set your custom presets in the \"Strings\" tab."]
FormattingType Setting_Formatting;

[Setting category="Commands" name="Enable map command" description="No information will be sent to the server if disabled"]
bool Setting_MapCommand = true;

[Setting category="Commands" name="Enable server command" description="No information will be sent to the server if disabled"]
bool Setting_ServerCommand = true;

[Setting category="Commands" name="Enable personnal best command" description="No information will be sent to the server if disabled"]
bool Setting_PbCommand = true;

[Setting category="Commands" name="Enable URL command" description="No information will be sent to the server if disabled"]
bool Setting_LinkCommand = true;

#if DEPENDENCY_CHECKPOINTCOUNTER
[Setting category="Commands" name="Enable CP command" description="No information will be sent to the server if disabled"]
bool Setting_CPCommand = true;
#else
bool Setting_CPCommand = false;
#endif

[Setting category="Strings" name="Not active" description="What will be displayed when you're not active anymore."]
string Setting_StringNotActive;

[Setting category="Strings" name="Current map" description="{name} {author} {author_time}"]
string Setting_StringCurrentMap;

[Setting category="Strings" name="Current server" description="{name} {nbr_player} {max_player}"]
string Setting_StringCurrentServer;

[Setting category="Strings" name="Current personnal best time" description="{pb}"]
string Setting_StringCurrentPersonnalBest;

[Setting category="Strings" name="Current map URL" description="{TMXurl} {TMIOurl}"]
string Setting_StringCurrentURL;

#if DEPENDENCY_CHECKPOINTCOUNTER
[Setting category="Strings" name="Current CP" description="{crt_cp} {max_cp}"]
string Setting_StringCurrentCP;
#else
string Setting_StringCurrentCP = "";
#endif

[Setting category="Strings" name="Not in a map"]
string Setting_StringNoCurrentMap;

[Setting category="Strings" name="Not in a server"]
string Setting_StringNoCurrentServer;

[Setting category="Strings" name="No personnal best time"]
string Setting_StringNoCurrentPersonnalBest;

[Setting category="Strings" name="Map not found"]
string Setting_StringNoCurrentURL;

// UI::ShowNotification(Icons::Check + " Twitch Chat Bot", "You are now connected and active !", UI::HSV(0.25, 0.5, 0.5));

string mapId = "";
string serverLogin = "";
int nbrPlayers = -1;
string previousTime = '';

bool isAuthenticated = false;
bool inMenu = true;
bool mapFound = false;
bool checkedInMenu = false;
bool bypass = false;
bool oldStatus = false;
string previousAuthenticated = '';
bool previousInMenu = true;

bool inGame = false;
bool strictMode = false;

string activeColor = "$F30";
string colorRed = "$F30";
string colorGreen = "$3C3";

string curMap = "";

string map_AT = "";

uint preCPIdx = 0;
uint curCP = 0;
uint maxCP = 0;
int previousCurrCP = 0;
int previousMaxCP = 0;
bool checkedNoCP = false;

string previousContentCP = "";
string previousContentPB = "";

CTrackMania@ g_app;
CTrackManiaNetwork@ network;
CGameCtnChallenge@ GetCurrentMap()
{
#if MP41 || TMNEXT
	return g_app.RootMap;
#else
	return g_app.Challenge;
#endif
}

void Main() {
	@g_app = cast<CTrackMania>(GetApp());
	@network = cast<CTrackManiaNetwork>(GetApp().Network);

	Setting_Username = network.PlayerInfo.Name;
	if(Setting_Username == ''){
		UI::ShowNotification(Icons::ExclamationTriangle + " Error !", "Couldn't get your Trackmania username !", UI::HSV(0, 0.5, 0.5));
	}

#if !DEPENDENCY_CHECKPOINTCOUNTER
	UI::ShowNotification(Icons::ExclamationTriangle + " Twitch Chat Bot", "Checkpoint Counter dependency not installed, checkpoint related commands will be disabled.", UI::HSV(.1, .8, .8));
	warn("Checkpoint Counter dependency not installed, checkpoint related commands will be disabled.");
#endif

	IsAuthenticated();

	while (true) {
		if(Setting_Active)
		{
			if(Setting_MapCommand) CheckMap();
			if(Setting_ServerCommand) ServerInfo();
			if(Setting_PbCommand) PbInfo();
			if(Setting_LinkCommand) Url();
			if(Setting_CPCommand) CPCounter();
		}
		yield();
	}
}

void OnDestroyed()
{
	Setting_Active = false;
	string json = '{"active":'+(Setting_Active ? "true" : "false")+', "custom_formatting_not_active":"'+Setting_StringNotActive+'"}';

	Net::HttpRequest req;
	req.Method = Net::HttpMethod::Post;
	req.Url = "https://tm-info.digit-egifts.fr/submit.php";
	req.Body = "type="+Net::UrlEncode("settings")+"&content="+Net::UrlEncode(json)+"&username="+Net::UrlEncode(Setting_Username)+"&key="+Net::UrlEncode(Setting_Key);
	req.Start();
	req.String();

}

void RenderMenu()
{
	if (!UI::BeginMenu("\\$60f" + Icons::Brands::Twitch + "\\$9cf\\$z Twitch Chat Bot")) {
		return;
	}
		if (UI::MenuItem("\\" + activeColor + Icons::Key + "\\$z Authenticate", "", false, !isAuthenticated)) {
			startnew(CoroutineFunc(Authenticate));
		}
		if (UI::MenuItem("\\$z" + Icons::PowerOff + "\\$z Active", "", Setting_Active)) {
			Setting_Active = !Setting_Active;
			activeColor = (Setting_Active ? colorGreen : colorRed);

			if(Setting_Active == true){
				startnew(CoroutineFunc(IsAuthenticated));
			}else{
				startnew(CoroutineFunc(SendStatus));
			}

		}
	UI::EndMenu();
}

void OnSettingsChanged()
{
	bypass = true;

	if(Setting_Active)
	{
		startnew(CoroutineFunc(SendSettings));
		if(Setting_MapCommand) startnew(CoroutineFunc(CheckMap));
		if(Setting_ServerCommand) startnew(CoroutineFunc(ServerInfo));
		if(Setting_PbCommand) startnew(CoroutineFunc(PbInfo));
		if(Setting_LinkCommand) startnew(CoroutineFunc(Url));
		if(Setting_CPCommand) startnew(CoroutineFunc(CPCounter));
		startnew(CoroutineFunc(SendStatus));
	}else{
		startnew(CoroutineFunc(SendStatus));
	}
	startnew(CoroutineFunc(IsAuthenticated));

	if(
		Setting_StringCurrentMap == ''
		|| Setting_StringCurrentServer == ''
		|| Setting_StringCurrentPersonnalBest == ''
		|| Setting_StringCurrentURL == ''
		|| Setting_StringNoCurrentMap == ''
		|| Setting_StringNoCurrentServer == ''
		|| Setting_StringNoCurrentPersonnalBest == ''
		|| Setting_StringNoCurrentURL == ''
		|| Setting_StringNotActive == ''
	){
		if(Setting_Formatting == FormattingType::Custom){
			UI::ShowNotification(Icons::ExclamationTriangle + " Error !", "You need to fill up every \"Strings\" fields !", UI::HSV(0, 0.5, 0.5));
		}
		Setting_Formatting = FormattingType::Fixed;
	}
}

string Replace(const string &in search, const string &in  replace, const string &in  subject)
{
	return Regex::Replace(subject, search, replace);
}

void SendInformations(const string &in  type, const string &in  content, const string &in  username, const string &in  key)
{
	print(type+": "+content);
	Net::HttpRequest req;
	req.Method = Net::HttpMethod::Post;
	req.Url = "https://tm-info.digit-egifts.fr/submit.php";
	req.Body = "type="+Net::UrlEncode(type)+"&content="+Net::UrlEncode(content)+"&username="+Net::UrlEncode(username)+"&key="+Net::UrlEncode(key);
	req.Start();
	while (!req.Finished()) {
		yield();
	}
}

void ResetServerInfo()
{
	serverLogin = '';
	nbrPlayers = -1;

	string json = '{"inServer":"false", "custom_formatting":"'+Setting_StringCurrentServer+'", "custom_formatting_false": "'+Setting_StringNoCurrentServer+'"}';
	SendInformations("server", json, Setting_Username, Setting_Key);
}

void IsAuthenticated()
{
	Net::HttpRequest req;
	req.Method = Net::HttpMethod::Get;
	req.Url = "https://tm-info.digit-egifts.fr/check-profile.php?username="+Setting_Username+"&private_key="+Setting_Key;
	req.Start();
	while (!req.Finished()) {
		yield();
	}
	string res = req.String();

	if(res == '1'){
		if(previousAuthenticated != res){
			previousAuthenticated = res;
			
			Setting_Active = true;
			isAuthenticated = true;
			activeColor = colorGreen;
			UI::ShowNotification(Icons::Check + " Twitch Chat Bot", "You are now connected and active !", UI::HSV(0.25, 0.5, 0.5));
		}
	}else{
		if(previousAuthenticated != res){
			previousAuthenticated = res;

			Setting_Active = false;
			isAuthenticated = false;
			activeColor = colorRed;
		}
	}
	startnew(CoroutineFunc(SendStatus));
}

void Url()
{
	auto currentMap = GetCurrentMap();
	if (currentMap !is null) {
		string UIDMap = currentMap.MapInfo.MapUid;

		string urlSearch = "https://trackmania.exchange/api/maps/get_map_info/multi/" + UIDMap;

		Net::HttpRequest req;
		req.Method = Net::HttpMethod::Get;
		req.Url = urlSearch;
		req.Start();
		while (!req.Finished()) {
			yield();
		}
		string response = req.String();

		// Evaluate reqest result
		Json::Value returnedObject = Json::Parse(response);
		try {
			if (returnedObject.Length > 0) {
				if(mapFound == false){
					mapFound = true;

					int g_MXId = returnedObject[0]["TrackID"];
					string json = '{"inMap":"true", "found":true, "tmxID":"'+g_MXId+'", "UID": "'+UIDMap+'", "custom_formatting":"'+Setting_StringCurrentURL+'", "custom_formatting_false": "'+Setting_StringNoCurrentURL+'"}';
					SendInformations("url", json, Setting_Username, Setting_Key);
				}
			} else {
				if(mapFound == true){
					mapFound = false;
					
					string json = '{"inMap":"true", "found":false, "custom_formatting":"'+Setting_StringCurrentURL+'", "custom_formatting_false": "'+Setting_StringNoCurrentURL+'"}';
					SendInformations("url", json, Setting_Username, Setting_Key);
				}
			}
		} catch {
			if(mapFound == true){
				mapFound = false;
				
				string json = '{"inMap":"true", "found":false, "custom_formatting":"'+Setting_StringCurrentURL+'", "custom_formatting_false": "'+Setting_StringNoCurrentURL+'"}';
				SendInformations("url", json, Setting_Username, Setting_Key);
			}
		}
	} else {
		if(checkedInMenu == false){
			checkedInMenu = true;

			string json = '{"inMap":"false", "found":false, "custom_formatting":"'+Setting_StringCurrentURL+'", "custom_formatting_false": "'+Setting_StringNoCurrentURL+'"}';
			SendInformations("url", json, Setting_Username, Setting_Key);
		}
	}
}

void ServerInfo()
{
	auto serverInfo = cast<CGameCtnNetServerInfo>(g_app.Network.ServerInfo);
	if (serverInfo.ServerLogin != "") {
		serverLogin = serverInfo.ServerLogin;
		string serverName = StripFormatCodes(serverInfo.ServerName);

		int numPlayers = g_app.Network.PlayerInfos.Length - 1;
		int maxPlayers = serverInfo.MaxPlayerCount;

		if(nbrPlayers != numPlayers){
			previousInMenu = false;
			nbrPlayers = numPlayers;

			string json = '{"inServer":"true", "name":"'+serverName+'","nbrPlayer":"'+numPlayers+'", "maxPlayer":"'+maxPlayers+'", "custom_formatting":"'+Setting_StringCurrentServer+'", "custom_formatting_false": "'+Setting_StringNoCurrentServer+'"}';
			SendInformations("server", json, Setting_Username, Setting_Key);
		}
	}else{
		if(previousInMenu == false){
			previousInMenu = true;

			ResetServerInfo();
		}
	}
}

void PbInfo()
{
	auto currentMap = GetCurrentMap();
	if (currentMap !is null) {
		checkedInMenu = false;
		auto network = cast<CTrackManiaNetwork>(@g_app.Network);
		string UIDMap = currentMap.MapInfo.MapUid;

		// Thanks Phlarx for this
		if(network.ClientManiaAppPlayground != null){
			auto userInfo = network.ClientManiaAppPlayground.UserMgr;
			MwId userId;
			if (userInfo.Users.Length > 0) {
				userId = userInfo.Users[0].Id;
			} else {
				userId.Value = uint(-1);
			}
			
			auto temps = network.ClientManiaAppPlayground.ScoreMgr.Map_GetRecord_v2(userId, UIDMap, "PersonalBest", "", "TimeAttack", "");

			if(temps != 4294967295 && temps != 0){
				string tmp = Setting_StringCurrentPersonnalBest;
				tmp = Replace("\\{pb\\}", StripFormatCodes(Time::Format(temps)), tmp);

				string json = '{"inMap":"true", "played":true, "pb":"'+Time::Format(temps)+'", "custom_formatting":"'+Setting_StringCurrentPersonnalBest+'", "custom_formatting_false": "'+Setting_StringCurrentPersonnalBest+'"}';
				if(previousContentPB != json){
					previousContentPB = json;
					SendInformations("pb", json, Setting_Username, Setting_Key);
				}
			} else {
				string tmp = Setting_StringNoCurrentPersonnalBest;

				string json = '{"inMap":"true", "played":false, "pb":"'+Time::Format(temps)+'", "custom_formatting":"'+Setting_StringCurrentPersonnalBest+'", "custom_formatting_false": "'+Setting_StringNoCurrentPersonnalBest+'"}';
				if(previousContentPB != json){
					previousContentPB = json;
					SendInformations("pb", json, Setting_Username, Setting_Key);
				}
			}
		}else{
			string json = '{"inMap":"false", "custom_formatting":"'+Setting_StringCurrentPersonnalBest+'", "custom_formatting_false": "'+Setting_StringCurrentPersonnalBest+'"}';
			if(previousContentPB != json){
				previousContentPB = json;
				SendInformations("pb", json, Setting_Username, Setting_Key);
			}
		}
	} else {
		string tmp = Setting_StringNoCurrentMap;
		if(checkedInMenu == false){
			checkedInMenu = true;

			string json = '{"inMap":"false", "custom_formatting":"'+Setting_StringCurrentPersonnalBest+'", "custom_formatting_false": "'+Setting_StringCurrentPersonnalBest+'"}';
			if(previousContentPB != json){
				previousContentPB = json;
				SendInformations("pb", json, Setting_Username, Setting_Key);
			}
		}
	}
}

void Authenticate()
{
	Net::HttpRequest req;
	req.Method = Net::HttpMethod::Get;
	req.Url = "https://password.markei.nl/randomsave.txt?count=1&min/max=16";
	req.Start();
	while (!req.Finished()) {
		yield();
	}
	string uniqueCode = req.String();

	string json = '{"api_state":"'+uniqueCode+'"}';
	SendInformations("settings", json, Setting_Username, Setting_Key);

	OpenBrowserURL('https://api.trackmania.com/oauth/authorize?response_type=code&client_id=915a708930788b5ecd10&scope=&redirect_uri=https://tm-info.digit-egifts.fr/redirect.php&state='+uniqueCode);
}

void SendStatus()
{
	if(oldStatus != Setting_Active){
		oldStatus = Setting_Active;

		string json = '{"active":'+(Setting_Active ? "true" : "false")+', "custom_formatting_not_active":"'+Setting_StringNotActive+'"}';
		SendInformations("settings", json, Setting_Username, Setting_Key);
	}
}

void SendSettings()
{
	string formattingType = "";
	switch (Setting_Formatting) {
		case FormattingType::Fixed: formattingType = "Fixed"; break;
		case FormattingType::Custom: formattingType = "Custom"; break;
	}
	
	string json = '{"formatting":"'+formattingType+'"}';
	SendInformations("settings", json, Setting_Username, Setting_Key);
}

void SendPb()
{
	// BUG: When you are out in TOTD
	// it says that you are not on a map
	auto currentMap = GetCurrentMap();
	if (currentMap !is null) {
		checkedInMenu = false;
		auto network = cast<CTrackManiaNetwork>(@g_app.Network);
		string UIDMap = currentMap.MapInfo.MapUid;

		// Thanks Phlarx for this
		if(network.ClientManiaAppPlayground != null){
			auto userInfo = network.ClientManiaAppPlayground.UserMgr;
			MwId userId;
			if (userInfo.Users.Length > 0) {
				userId = userInfo.Users[0].Id;
			} else {
				userId.Value = uint(-1);
			}
			
			auto temps = network.ClientManiaAppPlayground.ScoreMgr.Map_GetRecord_v2(userId, UIDMap, "PersonalBest", "", "TimeAttack", "");

			if(temps != 4294967295 && temps != 0){
				string tmp = Setting_StringCurrentPersonnalBest;
				tmp = Replace("\\{pb\\}", StripFormatCodes(Time::Format(temps)), tmp);

				string json = '{"inMap":"true", "played":true, "pb":"'+Time::Format(temps)+'", "custom_formatting":"'+Setting_StringCurrentPersonnalBest+'", "custom_formatting_false": "'+Setting_StringNoCurrentPersonnalBest+'"}';
				if(previousContentPB != json){
					previousContentPB = json;
					SendInformations("pb", json, Setting_Username, Setting_Key);
				}
			} else {
				string json = '{"inMap":"true", "played":false, "pb":"'+Time::Format(temps)+'", "custom_formatting":"'+Setting_StringCurrentPersonnalBest+'", "custom_formatting_false": "'+Setting_StringNoCurrentPersonnalBest+'"}';
				if(previousContentPB != json){
					previousContentPB = json;
					SendInformations("pb", json, Setting_Username, Setting_Key);
				}
			}
		}else{
			string json = '{"inMap":"false", "custom_formatting":"'+Setting_StringCurrentPersonnalBest+'", "custom_formatting_false": "'+Setting_StringNoCurrentPersonnalBest+'"}';
			if(previousContentPB != json){
				previousContentPB = json;
				SendInformations("pb", json, Setting_Username, Setting_Key);
			}
		}
	} else {
		string json = '{"inMap":"false", "custom_formatting":"'+Setting_StringCurrentPersonnalBest+'", "custom_formatting_false": "'+Setting_StringNoCurrentPersonnalBest+'"}';
		if(previousContentPB != json){
			previousContentPB = json;
			SendInformations("pb", json, Setting_Username, Setting_Key);
		}
	}
}

void SendUrl()
{
	auto currentMap = GetCurrentMap();
	if (currentMap !is null) {
		string UIDMap = currentMap.MapInfo.MapUid;

		string urlSearch = "https://trackmania.exchange/api/maps/get_map_info/multi/" + UIDMap;

		Net::HttpRequest req;
		req.Method = Net::HttpMethod::Get;
		req.Url = urlSearch;
		req.Start();
		while (!req.Finished()) {
			yield();
		}
		string response = req.String();

		// Evaluate reqest result
		Json::Value returnedObject = Json::Parse(response);
		try {
			if (returnedObject.Length > 0) {
				int g_MXId = returnedObject[0]["TrackID"];
				string json = '{"inMap":"true", "found":true, "tmxID":"'+g_MXId+'", "UID": "'+UIDMap+'", "custom_formatting":"'+Setting_StringCurrentURL+'", "custom_formatting_false": "'+Setting_StringNoCurrentURL+'"}';
				SendInformations("url", json, Setting_Username, Setting_Key);
			} else {
				string json = '{"inMap":"true", "found":false, "UID": "'+UIDMap+'", "custom_formatting":"'+Setting_StringCurrentURL+'", "custom_formatting_false": "'+Setting_StringNoCurrentURL+'"}';
				SendInformations("url", json, Setting_Username, Setting_Key);
			}
		} catch {
			string json = '{"inMap":"true", "found":false, "UID": "'+UIDMap+'", "custom_formatting":"'+Setting_StringCurrentURL+'", "custom_formatting_false": "'+Setting_StringNoCurrentURL+'"}';
				SendInformations("url", json, Setting_Username, Setting_Key);
		}
	} else {
		string json = '{"inMap":"false", "found":false, "custom_formatting":"'+Setting_StringCurrentURL+'", "custom_formatting_false": "'+Setting_StringNoCurrentURL+'"}';
		SendInformations("url", json, Setting_Username, Setting_Key);
	}
}

void CheckMap()
{
	auto currentMap = GetCurrentMap();
	if (currentMap !is null) {
		if(bypass == true  || (mapId != currentMap.EdChallengeId || inMenu == true))
		{
			mapId = currentMap.EdChallengeId;
			map_AT = Time::Format(currentMap.TMObjective_AuthorTime);

			string json = '{"inMap":"true", "name":"'+StripFormatCodes(currentMap.MapName)+'","author":"'+StripFormatCodes(currentMap.AuthorNickName)+'", "author_time":"'+StripFormatCodes(map_AT)+'", "custom_formatting":"'+Setting_StringCurrentMap+'", "custom_formatting_false": "'+Setting_StringNoCurrentMap+'"}';
			SendInformations("map", json, Setting_Username, Setting_Key);
			
			if(Setting_PbCommand) SendPb();
			if(Setting_LinkCommand) SendUrl();
			if(Setting_ServerCommand) ServerInfo();
			
			bypass = false;
		}

		inMenu = false;
		checkedInMenu = false;
	} else {
		inMenu = true;
		if(bypass == true || (inMenu == true && checkedInMenu == false)){
			checkedInMenu = true;
			
			string json = '{"inMap":"false", "custom_formatting":"'+Setting_StringCurrentMap+'", "custom_formatting_false": "'+Setting_StringNoCurrentMap+'"}';
			SendInformations("map", json, Setting_Username, Setting_Key);

			if(Setting_PbCommand) SendPb();
			if(Setting_LinkCommand) SendUrl();
			if(Setting_ServerCommand) ResetServerInfo();
			if(Setting_CPCommand) ResetCPCounter();
			bypass = false;
		}
	}
}


void ResetCPCounter()
{
	string json = '{"inMap":"false", "crt_cp": 0, "max_cp": 0, "custom_formatting":"'+Setting_StringCurrentMap+'", "custom_formatting_false": "'+Setting_StringNoCurrentMap+'"}';
	SendInformations("cp", json, Setting_Username, Setting_Key);
}

void CPCounter()
{
	if(!CP::inGame){
		string json = '{"inMap":"false", "crt_cp": 0, "max_cp": 0, "custom_formatting":"'+Setting_StringCurrentMap+'", "custom_formatting_false": "'+Setting_StringNoCurrentMap+'"}';
		if(previousContentCP != json){
			previousContentCP = json;
			SendInformations("cp", json, Setting_Username, Setting_Key);
		}
	}else{
		string json = '{"inMap":"true", "crt_cp": '+CP::curCP+', "max_cp": '+CP::maxCP+', "custom_formatting":"'+Setting_StringCurrentCP+'", "custom_formatting_false": ""}';
		if(previousContentCP != json){
			previousContentCP = json;
			SendInformations("cp", json, Setting_Username, Setting_Key);
		}
	}
}

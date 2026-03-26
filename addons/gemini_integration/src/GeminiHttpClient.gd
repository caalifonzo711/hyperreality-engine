extends Node
class_name GeminiHttpClient

# Simple helper to POST JSON and get back { ok, data / error }

func send_request(url: String, headers: PackedStringArray, body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http) # Temporary child so the request can run

	var json_body := JSON.stringify(body)

	var err := http.request(
		url,
		headers,
		HTTPClient.METHOD_POST,
		json_body
	)

	if err != OK:
		push_error("GeminiHttpClient: request() failed with error code %d" % err)
		return {
			"ok": false,
			"error": "request_failed",
			"code": err
		}

	var signal_result = await http.request_completed

	# Godot 4: signal args are (result, response_code, headers, body)
	var result_code: int = signal_result[0]
	var response_code: int = signal_result[1]
	var _resp_headers: PackedStringArray = signal_result[2]
	var resp_body: PackedByteArray = signal_result[3]

	if result_code != HTTPRequest.RESULT_SUCCESS:
		push_error("GeminiHttpClient: HTTP request failed, result=%d" % result_code)
		return {
			"ok": false,
			"error": "http_error",
			"code": result_code
		}

	var text := resp_body.get_string_from_utf8()
	var json := JSON.new()
	var parse_err := json.parse(text)

	if parse_err != OK:
		push_error("GeminiHttpClient: Failed to parse JSON response")
		return {
			"ok": false,
			"error": "json_parse_error",
			"raw": text
		}

	return {
		"ok": true,
		"status_code": response_code,
		"data": json.get_data()
	}

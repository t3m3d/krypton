// Tutorial 31: HTTP Client
// k:http makes web requests (via the system 'curl', shipped on Win10+,
// Linux, and macOS). Needs a network connection to reach a live server.
//
// k:http uses a Win32 temp-path call internally, so import head:fileio
// alongside it (header imports don't propagate out of a stdlib module).

import "head:fileio"
import "k:http"

just run {
    let url = "https://example.com"

    // httpStatus returns just the response code ("200", "404", ...),
    // or "0" if the request couldn't be made (offline / no curl).
    kp("status of " + url + ": " + httpStatus(url))

    // httpGet returns the response body as a string.
    let body = httpGet(url)
    kp("body length: " + len(body))

    // Also available:
    //   httpPost(url, body, contentType)
    //   httpGetWithHeaders(url, headers)   // headers = "Name: val\n..."
    //   httpDownload(url, path)            // stream to a file
}

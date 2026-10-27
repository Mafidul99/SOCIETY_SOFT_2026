<?php
declare(strict_types=1);


const APPS_SCRIPT_EXEC_URL = 'https://script.google.com/macros/s/AKfycbxUydf0GjWv6cEfEDWM7sd4UonrKsoaGwELUtkxajegoKcL28ata5FWJIvP5IYHP-DG/exec';
const MAX_REQUEST_BYTES = 500000;

header('Cache-Control: no-store');

function respond(int $status, string $message): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['status' => 'error', 'message' => $message]);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    respond(405, 'Only POST requests are supported.');
}

if (str_contains(APPS_SCRIPT_EXEC_URL, 'REPLACE_WITH_YOUR_DEPLOYMENT_ID')) {
    respond(503, 'Configure the Apps Script deployment URL in api.php.');
}

if (!function_exists('curl_init')) {
    respond(503, 'The hosting server does not have the PHP cURL extension enabled.');
}

$contentLength = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
if ($contentLength > MAX_REQUEST_BYTES) {
    respond(413, 'Request is too large.');
}

$body = file_get_contents('php://input');
if ($body === false || strlen($body) > MAX_REQUEST_BYTES) {
    respond(413, 'Request is too large.');
}

$curl = curl_init(APPS_SCRIPT_EXEC_URL);
if ($curl === false) {
    respond(502, 'Could not initialize the Apps Script connection.');
}

curl_setopt_array($curl, [
    CURLOPT_POST => true,
    CURLOPT_POSTFIELDS => $body,
    CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_MAXREDIRS => 5,
    CURLOPT_CONNECTTIMEOUT => 10,
    CURLOPT_TIMEOUT => 35,
]);

$responseBody = curl_exec($curl);
$curlError = curl_error($curl);
$status = (int) curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
$contentType = curl_getinfo($curl, CURLINFO_CONTENT_TYPE);
curl_close($curl);

if ($responseBody === false) {
    error_log('Apps Script proxy request failed: ' . $curlError);
    respond(502, 'Could not reach Apps Script. Check the deployment URL and hosting server connection.');
}

http_response_code($status > 0 ? $status : 502);
header(is_string($contentType) && $contentType !== ''
    ? 'Content-Type: ' . $contentType
    : 'Content-Type: application/json; charset=utf-8');
echo $responseBody;

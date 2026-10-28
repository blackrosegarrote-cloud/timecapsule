
<?php
// File storage for capsule attachments in Amazon S3.

use Aws\S3\S3Client;

// Create one S3 client and reuse it.
function storage_client(): S3Client
{
    static $client = null;

    if ($client === null) {
        $client = new S3Client([
            'version' => 'latest',
            'region' => config('AWS_REGION', 'eu-central-1'),
        ]);
    }

    return $client;
}

// Return the configured S3 bucket.
function storage_bucket(): string
{
    return config('S3_BUCKET');
}

// Save an uploaded file to S3 and return its random name.
function storage_save(array $uploadedFile, string $extension): string
{
    $storedName = bin2hex(random_bytes(16)) . '.' . $extension;

    $mime = mime_content_type($uploadedFile['tmp_name'])
        ?: 'application/octet-stream';

    storage_client()->putObject([
        'Bucket' => storage_bucket(),
        'Key' => 'uploads/' . $storedName,
        'SourceFile' => $uploadedFile['tmp_name'],
        'ContentType' => $mime,
    ]);

    return $storedName;
}

// Delete an object from S3.
function storage_delete(?string $storedName): void
{
    if ($storedName === null || $storedName === '') {
        return;
    }

    storage_client()->deleteObject([
        'Bucket' => storage_bucket(),
        'Key' => 'uploads/' . basename($storedName),
    ]);
}

// Redirect the browser to a presigned S3 URL.
// $disposition: "inline" or "attachment".
function storage_stream(
    string $storedName,
    string $mime,
    string $downloadName,
    string $disposition
): void {
    $asciiName = preg_replace(
        '/[^A-Za-z0-9._ -]/',
        '_',
        $downloadName
    );

    $disposition = $disposition === 'attachment'
        ? 'attachment'
        : 'inline';

    $contentDisposition = sprintf(
        '%s; filename="%s"; filename*=UTF-8\'\'%s',
        $disposition,
        $asciiName,
        rawurlencode($downloadName)
    );

    $client = storage_client();

    $command = $client->getCommand('GetObject', [
        'Bucket' => storage_bucket(),
        'Key' => 'uploads/' . basename($storedName),
        'ResponseContentType' => $mime,
        'ResponseContentDisposition' => $contentDisposition,
    ]);

    $request = $client->createPresignedRequest(
        $command,
        '+5 minutes'
    );

    $url = (string) $request->getUri();

    header('Location: ' . $url, true, 302);
    header('Cache-Control: no-store');
    exit;
}


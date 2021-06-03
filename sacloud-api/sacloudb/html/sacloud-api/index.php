<?php

require_once __DIR__ . '/vendor/autoload.php';
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Slim\Interfaces\RouteCollectorProxyInterface as Group;
use Slim\Factory\AppFactory;

$app = AppFactory::create();

$app->group('/external-api', function (Group $api) {
    $api->get('/config/authorized_keys', function (Request $request, Response $response, $args) {
        $text = file_get_contents("/home/sacloud-admin/.ssh/authorized_keys");
        $user = getenv("SACLOUDB_ADMIN_USER") . "@";
        $text = array_filter(explode("\n", $text), function($line) use ($user) { return strpos($line, $user) !== false;});
        $response->getBody()->write(implode("\n", $text));
        return $response->withHeader('Content-Type', 'text/plain')->withStatus(200);
    });

    $api->get('/ping', function (Request $request, Response $response, $args) {
        list($payload, $status, $headers) = maxscale_status();

        $json = json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        $response->getBody()->write($json);
        return $response->withHeader('Content-Type', 'application/json')->withStatus(200);
    });
    $api->get('/check_vip_connection', function (Request $request, Response $response, $args) {
        list($payload, $status, $headers) = bbb();

        $json = json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        $response->getBody()->write($json);
        return $response->withHeader('Content-Type', 'application/json')->withStatus(200);
    });

});

$app->group('/sacloud-api', function (Group $api) {
    $api->get('/status', function (Request $request, Response $response, $args) {
        list($payload, $status, $headers) = status_setting_response();

        $json = json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        $response->getBody()->write($json);
        return $response->withHeader('Content-Type', 'application/json')->withStatus(200);
    });
    $api->get('/parameter', function (Request $request, Response $response, $args) {
        $payload = settings_response("Parameter");

        $json = json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        $response->getBody()->write($json);
        return $response->withHeader('Content-Type', 'application/json')->withStatus(200);
    });
    $api->get('/plugin', function (Request $request, Response $response, $args) {
        $payload = settings_response("Plugin");

        $json = json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        $response->getBody()->write($json);
        return $response->withHeader('Content-Type', 'application/json')->withStatus(200);
    });
    $api->get('/syslog', function (Request $request, Response $response, $args) {
        $payload = settings_response("Syslog");

        $json = json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        $response->getBody()->write($json);
        return $response->withHeader('Content-Type', 'application/json')->withStatus(200);
    });
});

try {
    $app->run();
} catch ( Exception $e ){
    header("HTTP/1.0 " . $e->getCode() . " " . $e->getMessage());
    header("Content-Type: application/json");
    $payload = ["code" => $e->getCode(), "message" => $e->getMessage()];
    print json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
}


function status_setting_response() {
    $result = [
        "version" => [
            "lastmodified" => "2021-07-01 00:00:00 +0900",
            "commithash" => "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "status" => "latest",
            "tag" => "2.0",
            "expire" => "",
        ],
        "postgres" => [
            "status" => "running"
        ],
        "MariaDB" => [
            "status" => "running"
        ],
        "log" => [
            [
                "group" => "systemctl",
                "name" => "systemctl",
                "data" => "* postgresql-12.service - PostgreSQL 12 database server\n   Loaded: loaded (/usr/lib/sy,,,",
            ]
        ],
        "backup" => ["history" => []],
    ];

    return [$result];
}
function settings_response($name, $config = [], $settings = [], $form = []) {
    $payload = [];
    $payload[$name] = $config;
    $payload["Remark"] = [
        "Settings" => $settings,
        "Form" => $form,
    ];
    return $payload;
}

function maxscale_status() {
    if( !file_exists("/tmp/.maxctrl_output.txt")) {
        $result = [ "status" => "201 Created", "message" => "Still Setup" ];
    } else if((time() - filemtime("/tmp/.maxctrl_output.txt")) > 5) {
        $result = [ "status" => "307 Temporary Redirect", "message" => "Current Maxscale is gone." ];
    } else {
        $maxscale = file_get_contents("/tmp/.maxctrl_output.txt");
        if($maxscale == "") {
            sleep(1);
            $maxscale = file_get_contents("/tmp/.maxctrl_output.txt");
        }
        $lines = explode("\n", trim($maxscale));
        $services = [];
        foreach($lines as $line) {
            $a = array_values(explode("\t", $line));
            $services[] = [
                "host"        => $a[0],
                "ipaddr"      => $a[1],
                "port"        => $a[2],
                "connections" => $a[3],
                "status"      => $a[4],
                "gtid"        => $a[5],
            ];
        }
        if (strpos($services[0]['status'], "Master") !== false) {
            if (strpos($services[1]['status'], "Master") !== false) {
                    $result = [ "status" => "409 Conflict", "message" => "Duplicate Master" ];
            } else if (strpos($services[1]['status'], "Slave") !== false) {
                    $result = [ "status" => "200 Ok", "message" => "1:Primary, 2:Secondary" ];
            } else {
                    $result = [ "status" => "409 Conflict", "message" => "Not Found Master" ];
            }
        } else if(strpos($services[0]['status'], "Slave") !== false) {
            if (strpos($services[1]['status'], "Master") !== false) {
                    $result = [ "status" => "200 Ok", "message" => "1:Secondary, 2:Primary" ];
            } else if (strpos($services[1]['status'], "Slave") !== false) {
                    $result = [ "status" => "409 Conflict", "message" => "Not Found Master" ];
            } else {
                    $result = [ "status" => "409 Conflict", "message" => "Not Found Master" ];
            }
        } else {
            $result = [ "status" => "409 Conflict", "message" => "Not Found Master" ];
        }
    }
    $result["hostname"] = gethostname();
    $result["_detail"] = $services;
    return [$result, substr($result['status'], 3)];
}

function ping_vip_connection(){
    try {
        // ドライバ呼び出しを使用して MySQL データベースに接続します
        $dsn = "mysql:dbname=mysql;host=" . getenv("SACLOUDB_VIP_ADDRESS");
        $user = getenv("SACLOUDB_ADMIN_USER");
        $password = getenv("SACLOUDB_ADMIN_PASS");

        $dbh = new PDO($dsn, $user, $password);
        return [["status" => "200 Ok", "message" => "Ok" ]];
    } catch (PDOException $e) {
        return [["status" => "500 Server Internal Error", "message" => $e->getMessage() ]];
    }
}

<?php

require_once __DIR__ . '/vendor/autoload.php';

use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Slim\Interfaces\RouteCollectorProxyInterface as Group;
use Slim\Factory\AppFactory;

$app = AppFactory::create();

$app->group('/external-api', function (Group $api) {
    $api->get('/ping', function (Request $request, Response $response, $args) {
        list($payload, $status, $headers) = maxscale_status();

        return json_response($response, 302, $payload);
    });
});

$app->group('/sacloud-api', function (Group $api) {
    $api->get('/download-log/{file}.log', function (Request $request, Response $response, $args) {
        $util = EngineUtil::getEngineInstance();
        if (!$util->has_vip()) return $util->response_not_primary($response);

        $payload = $util->getLogFile($args["file"]);
        if ($payload) {
            return json_response($response, 200, $payload);
        } else {
            return json_response($response, 404, []);
        }
    });
    $api->put('/service-ctrl/restart', function (Request $request, Response $response, $args) {
        $util = EngineUtil::getEngineInstance();
        if (!$util->has_vip()) return $util->response_not_primary($response);

        list($result, $exit_code, $http_status) = $util->run_command("sacloudb/bin/execute-restart-database.sh");
        $payload = [
            "Accepted" => true,
            "_result" =>  $result,
            "_exit_code" =>  $exit_code,
        ];

        return json_response($response, 200, $payload);
    });
    $api->put('/config', function (Request $request, Response $response, $args) {
        $util = EngineUtil::getEngineInstance();
        list($payload, $status, $headers) = $util->status_setting_response();
        list($result, $exit_code, $http_status) = $util->run_command("sacloudb/bin/update-config.sh");

        $payload = array_merge($payload, [
            "_result" =>  $result,
            "_exit_code" =>  $exit_code,
        ]);
        return json_response($response, 302, $payload);
    });
    $api->get('/status', function (Request $request, Response $response, $args) {
        $util = EngineUtil::getEngineInstance();
        if (!$util->has_vip()) return $util->response_not_primary($response);

        list($payload, $status, $headers) = $util->status_setting_response();
        $payload = array_merge($payload, [
            "_vip_hostname" => $util->get_vip_hostname(),
            "_hostname" => gethostname(),
        ]);

        return json_response($response, 200, $payload);
    });
    $api->get('/parameter', function (Request $request, Response $response, $args) {
        $util = EngineUtil::getEngineInstance();
        if (!$util->has_vip()) return $util->response_not_primary($response);

        $payload = $util->settings_response("Parameter");

        $param = json_decode(@file_get_contents("/etc/my.cnf.d/zz_sacloudb.json"), true);
        $payload["Parameter"] = (array)@$param["Parameter"];


        $accepted = ["max_connections" => "max_connections", "version" => "version"];
        $payload["Remark"]["Form"] = array_values($util->getFormMap("Parameter", $param, $accepted));
        return json_response($response, 200, $payload);
    });

    $api->put('/parameter', function (Request $request, Response $response, $args) {
        $util = EngineUtil::getEngineInstance();
        if (!$util->has_vip()) return $util->response_not_primary($response);

        $data = $util->sacloudb_parsedBody($request->getBody()->getContents());
        $root = $util->sacloudb_parsedAttr($data,  "Parameter", "/");
        $sections = [
            "mysqld" => [],
        ];

        $accepted = ["max_connections" => "max_connections", "version" => "version"];
        $formMap = $util->getFormMap("Parameter", [], $accepted);

        $sql = [];
        foreach ($root["MariaDB"] as $_ => $file) {
            foreach ($sections as $sec => $_) {
                foreach ((array)$file[$sec] as $k => $v) {
                    if (strlen($v) > 0) $sections[$sec][] = "$k=$v";
                    // String
                    $is_numeric = isset($formMap[$k]["options"]["integer"]) ? $formMap[$k]["options"]["integer"] : false;
                    $is_reboot = (isset($formMap[$k]["options"]["reboot"]) ? $formMap[$k]["options"]["reboot"] : "dynamic") != "dynamic";
                    if ($is_numeric) {
                        $sql[] = "SET GLOBAL $k = $v;";
                    } else {
                        $sql[] = "SET GLOBAL $k = '$v';";
                    }
                }
            }
        }
        $conf = [];
        foreach ($sections as $name => $lines) {
            $conf[] = "[$name]";
            $conf = array_merge($conf, $lines);
            $conf[] = "\n";
        }

        file_put_contents("/etc/my.cnf.d/zz_sacloudb.json", json_encode($data));
        file_put_contents("/etc/my.cnf.d/zz_sacloudb.cnf", implode("\n", $conf));
        file_put_contents("/etc/my.cnf.d/zz_sacloudb.sql", implode("\n", $sql));

        $payload = ["Success" => true];
        return json_response($response, 303, $payload);
    });
    $api->get('/plugin', function (Request $request, Response $response, $args) {
        $util = EngineUtil::getEngineInstance();
        if (!$util->has_vip()) return $util->response_not_primary($response);

        $payload = $util->settings_response("Plugin");

        return json_response($response, 200, $payload);
    });
    $api->get('/syslog', function (Request $request, Response $response, $args) {
        $util = EngineUtil::getEngineInstance();
        if (!$util->has_vip()) return $util->response_not_primary($response);

        $payload = $util->settings_response("Syslog");

        return json_response($response, 200, $payload);
    });
    $api->get('/history[/]', function (Request $request, Response $response, $args) {
        $util = EngineUtil::getEngineInstance();
        if (!$util->has_vip()) return $util->response_not_primary($response);

        list($result, $exit_code, $http_status) = $util->run_command("sacloudb/bin/execute-list-backup.sh");
        $payload = [
            "Success" => true,
            "backup" => ["hisotry" => $result["files"]],
        ];

        return json_response($response, 200, $payload);
    });

    $api->post('/history[/]', function (Request $request, Response $response, $args) {
        $util = EngineUtil::getEngineInstance();
        if (!$util->has_vip()) return $util->response_not_primary($response);

        $data = $util->sacloudb_parsedBody($request->getBody()->getContents());
        $avail = isset($data["Settings"]["Settings"]["DBConf"]["backup"]["availability"])
            ? $data["Settings"]["Settings"]["DBConf"]["backup"]["availability"]
            : "unknown";
        $avail2lock = [
            "discontinued" => "unlock",
            "discontinued" => "locked",
            "unknown" => "locked",
        ];

        $lock = isset($avail2lock[$avail]) ? $avail2lock[$avail] : $avail2lock["unknown"];

        list($result, $exit_code, $http_status) = $util->run_command("sacloudb/bin/execute-dump-backup.sh", [$lock]);
        if ($exit_code != 0 && $result) return json_response($response, $http_status, $result);
        if ($exit_code != 0) throw new WebException("失敗しました");
        $payload = [
            "Accepted" => true,
        ];
        return json_response($response, 200, $payload);
    });

    $api->delete('/history/{timestamp}[/]', function (Request $request, Response $response, $args) {
        $util = EngineUtil::getEngineInstance();
        if (!$util->has_vip()) return $util->response_not_primary($response);

        $timestamp = $args["timestamp"];
        list($result, $exit_code, $http_status) = $util->run_command("sacloudb/bin/execute-lock-backup.sh", ["delete", $timestamp]);
        $payload = [($exit_code == 0 ? "is_ok" : "is_fatal") => true];
        return json_response($response, $http_status, $payload);
    });

    $api->put('/history-lock/{timestamp}[/]', function (Request $request, Response $response, $args) {
        $util = EngineUtil::getEngineInstance();
        if (!$util->has_vip()) return $util->response_not_primary($response);

        $timestamp = $args["timestamp"];
        list($result, $exit_code, $http_status) = $util->run_command("sacloudb/bin/execute-lock-backup.sh", ["locked", $timestamp]);
        $payload = [($exit_code == 0 ? "is_ok" : "is_fatal") => true];
        return json_response($response, $http_status, $payload);
    });

    $api->delete('/history-lock/{timestamp}[/]', function (Request $request, Response $response, $args) {
        $util = EngineUtil::getEngineInstance();
        if (!$util->has_vip()) return $util->response_not_primary($response);

        $timestamp = $args["timestamp"];
        list($result, $exit_code, $http_status) = $util->run_command("sacloudb/bin/execute-lock-backup.sh", ["unlock", $timestamp]);
        $payload = [($exit_code == 0 ? "is_ok" : "is_fatal") => true];
        return json_response($response, $http_status, $payload);
    });

    $api->get('/primary[/]', function (Request $request, Response $response, $args) {
        $util = EngineUtil::getEngineInstance();
        if (!$util->has_vip()) return $util->response_not_primary($response);
        $payload = [
            "Accepted" => true,
            "Server" => [
                "ID" => getenv("SACLOUDB_SERVER_ID"),
                "Interfaces" => [
                    [
                        "IPAddress" => getenv("SACLOUDB_SERVER_GLOBALIP"),
                    ],
                    [
                        "UserIPAddress" => getenv("SACLOUDB_LOCAL_ADDRESS"),
                        "VirtualIPAddress" => getenv("SACLOUDB_VIP_ADDRESS"),
                    ],
                ]
            ],
        ];
        return json_response($response, 200, $payload);
    });
});

try {
    $app->run();
} catch (Exception $e) {
    header("HTTP/1.0 " . $e->getCode() . " " . $e->getMessage());
    header("Content-Type: application/json");
    $payload = ["code" => $e->getCode(), "message" => $e->getMessage()];
    print json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
}

function json_response($response, $code, $payload)
{
    $json = json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    $response->getBody()->write($json);
    return $response->withHeader('Content-Type', 'application/json')->withStatus($code);
}

class WebException extends Exception
{
}

class EngineUtil
{

    public static function getEngineInstance()
    {
        $name = self::get_appliance_dbconf("DatabaseName");
        if ($name == "MariaDB") return new MariaDBEngineUtil();
        if ($name == "postgres") return new PostgresDBEngineUtil();
        throw new WebException();
    }
    public static function get_appliance_dbconf($key = null)
    {
        $json = json_decode(file_get_contents("/tmp/.status/appliance.json"), true);
        $dbconf = $json["Appliance"]["Remark"]["DBConf"];
        if ($key == null) {
            return $dbconf;
        } else if (isset($dbconf["Common"][$key])) {
            return $dbconf["Common"][$key];
        } else {
            throw new Exception();
        }
    }

    public static function run_command($cmd, $args = [])
    {
        $escaped_args = implode(" ", array_map(function ($arg) {
            return escapeshellarg($arg);
        }, $args));
        $command = "ssh root@localhost " . escapeshellcmd("/root/.sacloud-api/$cmd") . " $escaped_args";
        $result = exec($command, $output, $result_code);
        if ($result === false) throw new WebException("$command, $result_code");

        $http_status = 200;
        $output = json_decode(implode("\n", $output), true);
        if ($result_code != 0) $http_status = 500;
        if (isset($output["status_code"])) $http_status = $output["status_code"];
        return [$output, $result_code, $http_status];
    }

    function sacloudb_parsedBody($contents)
    {
        if (substr($contents, 0, 5) === "data=") {
            parse_str($contents, $out);
            return json_decode($out["data"], true);
        } else {
            return json_decode($contents, true);
        }
    }

    function sacloudb_parsedAttr($data, $category, $sep)
    {
        $root = [];
        foreach ($data[$category]["Attr"] as $key => $value) {
            $a = explode($sep, $key);
            $name = array_pop($a);
            $cur = &$root;
            foreach ($a as $k) {
                if (!isset($cur[$k])) $cur[$k] = [];
                $cur = &$cur[$k];
            }
            $cur[$name] = $value;
        }
        return $root;
    }

    function status_setting_response()
    {
        $databaseType = self::get_appliance_dbconf("DatabaseName");
        $logs = [
            [
                "group" => "systemctl",
                "name" => "systemctl",
                "data" => file_get_contents("/tmp/.status/systemctl.txt"),
            ],
        ];

        $backup = @file_get_contents("/mnt/backup/files.cache.json");
        if ($backup) $backup = json_decode($backup, true);
        $result = [
            "version" => [
                "lastmodified" => "2021-07-01 00:00:00 +0900",
                "commithash" => "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "status" => "latest",
                "tag" => "2.0",
                "expire" => "",
            ],
            "$databaseType" => [
                "status" => "running"
            ],
            "log" => array_values(array_merge($logs, $this->getLogs())),
            "backup" => ["history" => isset($backup["files"]) ? $backup["files"] : []],
        ];

        return [$result, [], []];
    }

    function settings_response($name, $config = [], $settings = [], $form = [])
    {
        $payload = [];
        $payload[$name] = $config;
        $payload["Remark"] = [
            "Settings" => $settings,
            "Form" => $form,
        ];
        return $payload;
    }

    function response_not_primary($response)
    {
        return json_response($response, 303, ["Message" => "is not primary"]);
    }

    public function has_vip()
    {
        return $this->get_vip_hostname() == gethostname();
    }

    public function getLogs()
    {
        return [];
    }
    public function getLogFile($name)
    {
        return [];
    }
    public function get_vip_hostname()
    {
        return [];
    }
}

class MariaDBEngineUtil extends EngineUtil
{
    function executeQuery($ipaddr, $sql, $args = [])
    {
        // ドライバ呼び出しを使用して MySQL データベースに接続します
        $dsn = "mysql:dbname=mysql;host=$ipaddr";
        $user = getenv("SACLOUDB_ADMIN_USER");
        $password = getenv("SACLOUDB_ADMIN_PASS");
        try {
            $dbh = new PDO($dsn, $user, $password);
            $stmt = $dbh->query($sql);
            return $stmt->fetch(PDO::FETCH_ASSOC);
        } catch (PDOException $e) {
            return [["status" => "500 Server Internal Error", "message" => $e->getMessage()]];
        }
    }
    function executeQueryVIP($sql, $args = [])
    {
        return $this->executeQuery(getenv("SACLOUDB_VIP_ADDRESS"), $sql, $args);
    }
    function executeQueryLocal($sql, $args = [])
    {
        return $this->executeQuery(getenv("SACLOUDB_LOCAL_ADDRESS"), $sql, $args);
    }

    function get_vip_hostname()
    {
        $result = $this->executeQueryVIP("SHOW VARIABLES WHERE Variable_name = 'hostname';");
        return $result ? $result["Value"] : null;
    }
    function getLogs()
    {
        $logs = [];
        $logs[] = [
            "group" => "mariadb",
            "name" => "error.log",
            "data" => "..." . mb_substr(file_get_contents("/var/lib/mysql/error.log"), -1000),
            "size" => filesize("/var/lib/mysql/error.log"),
        ];
        return $logs;
    }
    function getLogFile($name)
    {
        $file = "/var/lib/mysql/" . basename($name) . ".log";
        if (file_exists($file)) {
            return [
                "Log" => file_get_contents($file),
                "FileName" => $file
            ];
        } else {
            return false;
        }
    }

    function getFormMap($name, $param, $accepted)
    {
        if ($name != "Parameter") throw new WebException("");

        $text = file_get_contents(__DIR__ . "/notes/113200007922");
        $text = str_replace('$CLOUD_APPLIANCE_DATABASE_SERVICE_PORT', 3306, $text);
        $json = json_decode($text, true);

        $formMap = [];
        foreach ($json["Form"] as $item) {
            $a = explode("/", $item["name"]);
            if ($a[0] !== "MariaDB") continue;
            $name = array_pop($a);
            if ($name === "port") continue;

            if (isset($param["Parameter"]["Attr"][$item["name"]])) {
                $item["options"]["default"] = $param["Parameter"]["Attr"][$item["name"]];
            }
            if (isset($accepted[$name])) $formMap[$accepted[$name]] = $item;
        }
        return $formMap;
    }
}

class PostgresDBEngineUtil extends EngineUtil
{
    function getLogs()
    {
        // FIXME
        $logs = [];
        $PGDATA = "/var/lib/pgsql/13/data";
        $files = glob("$PGDATA/log/postgresql-*.log");
        usort($files, function ($a, $b) {
            return - (filemtime($b) - filemtime($a));
        });
        foreach ($files as $file) {
            if (is_file($file)) {
                $logs[] = [
                    "group" => "postgres",
                    "name" => basename($file),
                    "data" => "..." . mb_substr(file_get_contents($file), -1000),
                    "size" => filesize($file),
                ];
            }
        }
        return $logs;
    }
    function getLogFile($name)
    {
        // TODO ログ取得
        $PGDATA = "/var/lib/pgsql/13/data";
        $file = "$PGDATA/log/" . basename($name);

        return [
            "Log" => file_get_contents($file),
            "FileName" => $file
        ];
    }
}

function maxscale_status()
{
    if (!file_exists("/tmp/.maxctrl_output.txt")) {
        $result = ["status" => "201 Created", "message" => "Still Setup"];
    } else if ((time() - filemtime("/tmp/.maxctrl_output.txt")) > 5) {
        $result = ["status" => "307 Temporary Redirect", "message" => "Current Maxscale is gone."];
    } else {
        $maxscale = file_get_contents("/tmp/.maxctrl_output.txt");
        if ($maxscale == "") {
            sleep(1);
            $maxscale = file_get_contents("/tmp/.maxctrl_output.txt");
        }
        $lines = explode("\n", trim($maxscale));
        $services = [];
        foreach ($lines as $line) {
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
                $result = ["status" => "409 Conflict", "message" => "Duplicate Master"];
            } else if (strpos($services[1]['status'], "Slave") !== false) {
                $result = ["status" => "200 Ok", "message" => "1:Primary, 2:Secondary"];
            } else {
                $result = ["status" => "409 Conflict", "message" => "Not Found Master"];
            }
        } else if (strpos($services[0]['status'], "Slave") !== false) {
            if (strpos($services[1]['status'], "Master") !== false) {
                $result = ["status" => "200 Ok", "message" => "1:Secondary, 2:Primary"];
            } else if (strpos($services[1]['status'], "Slave") !== false) {
                $result = ["status" => "409 Conflict", "message" => "Not Found Master"];
            } else {
                $result = ["status" => "409 Conflict", "message" => "Not Found Master"];
            }
        } else {
            $result = ["status" => "409 Conflict", "message" => "Not Found Master"];
        }
    }
    $result["hostname"] = gethostname();
    $result["_detail"] = $services;
    return [$result, substr($result['status'], 3)];
}

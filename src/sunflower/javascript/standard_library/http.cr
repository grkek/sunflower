# Async HTTP client for the Medusa/QuickJS sandbox.
#
# JS API:
#   import { request, get, post, put, patch, del, download } from "http";
#
#   const res = await get("https://example.com");
#   const res = await post("https://api.example.com/data", { key: "value" });
#   const res = await request({ url: "...", method: "PUT", headers: { ... }, body: "..." });
#   await download("https://example.com/file.zip", "/tmp/file.zip");

module Sunflower
  module JavaScript
    module StandardLibrary
      class HTTP < Module
        def register(sandbox : Medusa::Sandbox, engine : Engine) : Nil
          register_native_bindings(sandbox, engine)
          install_js_module(sandbox)
        end

        private def register_native_bindings(sandbox, engine) : Nil
          sandbox.bind("__http_request", 1) do |args|
            opts = JSON.parse(args[0].as_s)
            promise_id = Random::Secure.hex(8)
            spawn do
              begin
                url = opts["url"].as_s
                method = (opts["method"]?.try(&.as_s) || "GET").upcase
                body = opts["body"]?.try(&.as_s)
                headers = ::HTTP::Headers.new
                if h = opts["headers"]?.try(&.as_h)
                  h.each { |k, v| headers[k] = v.as_s }
                end
                response = case method
                           when "POST"   then ::HTTP::Client.exec("POST", url, headers: headers, body: body)
                           when "PUT"    then ::HTTP::Client.exec("PUT", url, headers: headers, body: body)
                           when "PATCH"  then ::HTTP::Client.exec("PATCH", url, headers: headers, body: body)
                           when "DELETE" then ::HTTP::Client.exec("DELETE", url, headers: headers)
                           when "HEAD"   then ::HTTP::Client.exec("HEAD", url, headers: headers)
                           else               ::HTTP::Client.exec("GET", url, headers: headers)
                           end
                response_headers = {} of String => String
                response.headers.each { |k, v| response_headers[k] = v.join(", ") }
                engine.resolve_promise(promise_id, {
                  status: response.status_code, statusMessage: response.status_message,
                  headers: response_headers, body: response.body,
                }.to_json)
              rescue ex
                engine.resolve_promise(promise_id, {error: ex.message}.to_json)
              end
            end
            promise_id
          end

          sandbox.bind("__http_download", 2) do |args|
            url = args[0].as_s
            path = args[1].as_s
            promise_id = Random::Secure.hex(8)
            spawn do
              begin
                response = ::HTTP::Client.get(url)
                if response.success?
                  File.write(path, response.body)
                  engine.resolve_promise(promise_id, {ok: true, bytes: response.body.bytesize, path: path}.to_json)
                else
                  engine.resolve_promise(promise_id, {error: "HTTP #{response.status_code}", status: response.status_code}.to_json)
                end
              rescue ex
                engine.resolve_promise(promise_id, {error: ex.message}.to_json)
              end
            end
            promise_id
          end
        end

        private def install_js_module(sandbox) : Nil
          ModuleLoader.register("http", <<-JS)
            export function request(opts) {
              if (typeof opts === 'string') opts = { url: opts };
              return __createPromise(__http_request(JSON.stringify(opts)));
            }

            export function get(url, headers) {
              return request({ url: url, method: 'GET', headers: headers });
            }

            export function post(url, body, headers) {
              return request({
                url: url, method: 'POST',
                body: typeof body === 'object' ? JSON.stringify(body) : body,
                headers: headers
              });
            }

            export function put(url, body, headers) {
              return request({
                url: url, method: 'PUT',
                body: typeof body === 'object' ? JSON.stringify(body) : body,
                headers: headers
              });
            }

            export function patch(url, body, headers) {
              return request({
                url: url, method: 'PATCH',
                body: typeof body === 'object' ? JSON.stringify(body) : body,
                headers: headers
              });
            }

            export function del(url, headers) {
              return request({ url: url, method: 'DELETE', headers: headers });
            }

            export function download(url, path) {
              return __createPromise(__http_download(url, path));
            }
          JS
        end
      end
    end
  end
end

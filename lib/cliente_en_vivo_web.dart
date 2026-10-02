import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

http.Client crearClienteEnVivo() => FetchClient(mode: RequestMode.cors);

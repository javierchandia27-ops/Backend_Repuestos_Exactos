import 'package:dart_frog/dart_frog.dart';
import 'package:re_api/auth/authentication_middleware.dart';

Handler middleware(Handler handler) => handler.use(authenticationMiddleware());

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:re_api/features/catalog/repositories/catalog_repository.dart';
import 'package:re_api/features/catalog/services/catalog_service.dart';

Handler middleware(Handler handler) => handler.use(
  provider<CatalogService>(
    (context) => CatalogService(CatalogRepository(context.read<TxSession>())),
  ),
);

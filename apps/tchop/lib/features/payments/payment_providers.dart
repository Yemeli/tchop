/// Payment provider catalog for Project Tchop (BYO credentials).
///
/// Pure Dart (no Flutter import) so it can be unit-tested without the SDK.
///
/// Each restaurant connects its OWN accounts: money settles directly into
/// the restaurant's provider accounts — the platform never holds funds.
/// The credential *fields* below are what the merchant pastes into the app;
/// the values live in device memory only until the `payments/credentials_save`
/// outbox op is acknowledged, and are encrypted server-side via Supabase
/// Vault before insert.
library;

/// One input the merchant must supply for a provider.
class CredentialField {
  const CredentialField({
    required this.key,
    required this.labelFr,
    required this.helperFr,
    this.obscure = true,
  });

  /// Key used in the `secret` JSON blob sent to the edge function.
  final String key;

  /// French label shown above the field.
  final String labelFr;

  /// French helper text: where the merchant finds this value.
  final String helperFr;

  /// Whether the field is masked while typing.
  final bool obscure;
}

/// A payment provider (rail) a restaurant can connect.
class PaymentProvider {
  const PaymentProvider({
    required this.id,
    required this.nameFr,
    required this.subtitleFr,
    required this.fields,
    required this.verifyHintFr,
  });

  /// DB value, matches the CHECK constraint on tenant_payment_credentials.
  final String id;

  /// French display name.
  final String nameFr;

  /// One-line French description of the rail.
  final String subtitleFr;

  /// Credential fields the merchant fills in.
  final List<CredentialField> fields;

  /// French note about what "Tester la connexion" does for this provider.
  final String verifyHintFr;
}

const List<PaymentProvider> paymentProviders = [
  PaymentProvider(
    id: 'mtn_momo',
    nameFr: 'MTN Mobile Money',
    subtitleFr: 'Collections API · XAF',
    verifyHintFr:
        'Tente un appel au bac à sable MTN. Si le bac à sable est injoignable, '
        'le test est marqué « Mode démo » — jamais comme un succès.',
    fields: [
      CredentialField(
        key: 'api_user',
        labelFr: 'API User',
        helperFr:
            'Dans le portail développeur MTN MoMo (momodeveloper.mtn.com) : '
            'créez un utilisateur API pour votre abonnement Collections, '
            'puis copiez l’« API User » affiché.',
      ),
      CredentialField(
        key: 'api_key',
        labelFr: 'Clé API',
        helperFr:
            'Toujours dans le portail MTN : générez la clé de cet utilisateur '
            'API (« API Key »). Elle ne s’affiche qu’une seule fois — '
            'copiez-la immédiatement.',
      ),
      CredentialField(
        key: 'subscription_key',
        labelFr: 'Clé d’abonnement (Ocp-Apim-Subscription-Key)',
        helperFr:
            'Dans votre profil du portail MTN, rubrique « Subscriptions » : '
            'copiez la clé primaire de votre produit Collections.',
      ),
    ],
  ),
  PaymentProvider(
    id: 'orange_money',
    nameFr: 'Orange Money',
    subtitleFr: 'WebPay · XAF',
    verifyHintFr:
        'Tente un appel au bac à sable Orange. Bac à sable injoignable → '
        '« Mode démo », jamais un succès simulé.',
    fields: [
      CredentialField(
        key: 'merchant_key',
        labelFr: 'Clé marchand',
        helperFr:
            'Demandez votre clé marchand auprès du service entreprises '
            'Orange Money de votre pays, puis collez-la ici. Elle identifie '
            'votre commerce pour recevoir les paiements.',
      ),
    ],
  ),
  PaymentProvider(
    id: 'wave',
    nameFr: 'Wave',
    subtitleFr: 'Paiements Wave · XAF',
    verifyHintFr:
        'Tente un appel au bac à sable Wave. Bac à sable injoignable → '
        '« Mode démo ».',
    fields: [
      CredentialField(
        key: 'api_key',
        labelFr: 'Clé API Wave',
        helperFr:
            'Dans votre espace marchand Wave : générez une clé API '
            'pour votre commerce et collez-la ici.',
      ),
    ],
  ),
  PaymentProvider(
    id: 'cinetpay',
    nameFr: 'CinetPay',
    subtitleFr: 'Agrégateur · cartes & mobile money · XAF',
    verifyHintFr:
        'Tente un appel au bac à sable CinetPay. Bac à sable injoignable → '
        '« Mode démo ».',
    fields: [
      CredentialField(
        key: 'site_id',
        labelFr: 'Site ID',
        helperFr:
            'Dans votre tableau de bord CinetPay : copiez le « Site ID » '
            'de votre site marchand.',
      ),
      CredentialField(
        key: 'api_key',
        labelFr: 'Clé API (apikey)',
        helperFr:
            'Dans votre tableau de bord CinetPay : copiez votre « API Key ». '
            'Utilisez la clé de TEST pour essayer, la clé LIVE pour encaisser.',
      ),
    ],
  ),
  PaymentProvider(
    id: 'flutterwave',
    nameFr: 'Flutterwave',
    subtitleFr: 'Agrégateur · cartes & mobile money · XAF',
    verifyHintFr:
        'Tente un appel au bac à sable Flutterwave. Bac à sable injoignable '
        '→ « Mode démo ».',
    fields: [
      CredentialField(
        key: 'secret_key',
        labelFr: 'Clé secrète',
        helperFr:
            'Dans votre tableau de bord Flutterwave, rubrique « Settings › '
            'API Keys » : copiez la clé secrète (commence par FLWSECK_TEST_ '
            'en test, FLWSECK_ en production).',
      ),
    ],
  ),
  PaymentProvider(
    id: 'card',
    nameFr: 'Carte bancaire',
    subtitleFr: 'Via agrégateur (CinetPay / Flutterwave)',
    verifyHintFr:
        'Les cartes transitent par votre compte CinetPay ou Flutterwave : '
        'connectez l’un de ces agrégateurs ci-dessus.',
    fields: [],
  ),
];

/// Looks up a provider by its DB id, or null for unknown ids.
PaymentProvider? paymentProviderById(String id) {
  for (final p in paymentProviders) {
    if (p.id == id) return p;
  }
  return null;
}

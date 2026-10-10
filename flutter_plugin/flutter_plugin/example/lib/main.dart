import 'package:dlc_wallet/dlc_wallet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DLC Bitcoin Wallet',
      theme: ThemeData(
        primarySwatch: Colors.orange,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: WalletScreen(),
    );
  }
}

class WalletScreen extends StatefulWidget {
  @override
  _WalletScreenState createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  // Wallet state
  String _xpub = '';
  String _status = 'Not initialized';
  bool _isLoading = false;
  bool _isInitialized = false;

  // Controllers
  final TextEditingController _entropyController = TextEditingController();
  final TextEditingController _networkController = TextEditingController(text: 'signet');
  final TextEditingController _indexController = TextEditingController(text: '0');
  final TextEditingController _hashController = TextEditingController();

  // Address management
  List<Map<String, String>> _addresses = [];

  // DLC setup
  Map<String, dynamic>? _dlcSetup;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // Example entropy (12 words "oil" repeated)
    _entropyController.text = "99d33a674ce99d33a674ce99d33a674c";
    _hashController.text = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
  }

  @override
  void dispose() {
    _tabController.dispose();
    _entropyController.dispose();
    _networkController.dispose();
    _indexController.dispose();
    _hashController.dispose();
    super.dispose();
  }

  // ==================== WALLET INITIALIZATION ====================

  Future<void> _initializeWallet() async {
    setState(() {
      _isLoading = true;
      _status = 'Initializing wallet...';
    });

    try {
      final xpub = await DlcWallet.initWithEntropy(
        _entropyController.text,
        _networkController.text,
      );

      setState(() {
        _xpub = xpub;
        _status = 'Wallet initialized successfully';
        _isInitialized = true;
      });

      // Auto-load addresses
      await _loadAddresses();
    } catch (e) {
      setState(() {
        _status = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAddresses() async {
    try {
      final addresses = await DlcWallet.generateAddresses(5);
      setState(() {
        _addresses = addresses;
      });
    } catch (e) {
      setState(() {
        _status = 'Error loading addresses: ${e.toString()}';
      });
    }
  }

  // ==================== SIGNING OPERATIONS ====================

  Future<void> _signHash() async {
    if (!_isInitialized) {
      _showError('Wallet not initialized');
      return;
    }

    try {
      final index = int.parse(_indexController.text);
      final index4 = 0;
      final publicKey = await DlcWallet.getPublicKey(index);
      final signature = await DlcWallet.signHashEcdsa(
        _hashController.text,
        index,
        index4,
        publicKey,
      );

      _showResult('ECDSA Signature', signature);
    } catch (e) {
      _showError('Signing failed: ${e.toString()}');
    }
  }

  Future<void> _createNonce() async {
    if (!_isInitialized) {
      _showError('Wallet not initialized');
      return;
    }

    try {
      final nonce = await DlcWallet.createDeterministicNonce(
        'test_event_${DateTime.now().millisecondsSinceEpoch}',
        int.parse(_indexController.text),
      );

      _showResult('Deterministic Nonce', 'Secret: ${nonce['secret']}\nPublic: ${nonce['public']}');
    } catch (e) {
      _showError('Nonce creation failed: ${e.toString()}');
    }
  }

  Future<void> _signTransaction() async {
    if (!_isInitialized) {
      _showError('Wallet not initialized');
      return;
    }

    try {
      final signature = await DlcWallet.signTransaction(
        _hashController.text,
        int.parse(_indexController.text),
        0,
      );

      _showResult('Transaction Signature', signature);
    } catch (e) {
      _showError('Transaction signing failed: ${e.toString()}');
    }
  }

  // ==================== DLC OPERATIONS ====================

  Future<void> _createDlcSetup() async {
    if (!_isInitialized) {
      _showError('Wallet not initialized');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Creating DLC setup...';
    });

    try {
      final dlcSetup = await DlcWallet.createDlcSetup(
        eventId: 'btc_price_${DateTime.now().millisecondsSinceEpoch}',
        keyIndex: int.parse(_indexController.text),
        digitStringTemplate: 'BTCUSD',
        oraclePublicKey: '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
        intervalWildcards: ['50000-60000', '60000-70000', '70000-80000'],
        sighashes: [
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          'a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3',
          'b5d4045c3f466fa91fe2cc6abe79232a1a57cdf104f7eceb4e05cb9c1b2c8b7a',
        ],
        numDigits: 2,
      );

      setState(() {
        _dlcSetup = dlcSetup;
        _status = 'DLC setup created successfully';
      });
    } catch (e) {
      setState(() {
        _status = 'DLC setup failed: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createCetAdaptorSigs() async {
    if (!_isInitialized) {
      _showError('Wallet not initialized');
      return;
    }

    try {
      final signatures = await DlcWallet.createCetAdaptorSigs(
        numDigits: 2,
        numCets: 3,
        digitStringTemplate: 'BTCUSD',
        oraclePublicKey: '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
        signingKeyIndex: int.parse(_indexController.text),
        signingKeyIndex4: 0,
        signingPublicKey: await DlcWallet.getPublicKey(int.parse(_indexController.text)),
        nonces: [
          '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
          '02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9',
        ],
        intervalWildcards: ['50000-60000', '60000-70000', '70000-80000'],
        sighashes: [
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          'a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3',
          'b5d4045c3f466fa91fe2cc6abe79232a1a57cdf104f7eceb4e05cb9c1b2c8b7a',
        ],
      );

      _showResult('CET Adaptor Signatures', signatures.join('\n'));
    } catch (e) {
      _showError('CET signature creation failed: ${e.toString()}');
    }
  }

  // ==================== UI HELPERS ====================

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showResult(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: SelectableText(
            content,
            style: TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String content) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                content,
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== BUILD UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('DLC Bitcoin Wallet'),
        backgroundColor: Colors.orange,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Wallet'),
            Tab(text: 'Signing'),
            Tab(text: 'DLC'),
            Tab(text: 'Addresses'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWalletTab(),
          _buildSigningTab(),
          _buildDlcTab(),
          _buildAddressesTab(),
        ],
      ),
    );
  }

  Widget _buildWalletTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status Card
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(_status),
                ],
              ),
            ),
          ),

          SizedBox(height: 16),

          // Initialization Section
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Initialize Wallet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: _entropyController,
                    decoration: InputDecoration(
                      labelText: 'Entropy (hex)',
                      hintText: 'Enter wallet entropy in hex format',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: _networkController,
                    decoration: InputDecoration(
                      labelText: 'Network',
                      hintText: 'bitcoin or signet',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _initializeWallet,
                      child: _isLoading ? CircularProgressIndicator() : Text('Initialize Wallet'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 16),

          // Wallet Info
          if (_xpub.isNotEmpty) _buildInfoCard('Extended Public Key', _xpub),
        ],
      ),
    );
  }

  Widget _buildSigningTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Signing Operations',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: _indexController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Key Index',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: _hashController,
                    decoration: InputDecoration(
                      labelText: 'Hash (hex)',
                      hintText: 'Enter hash to sign',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _signHash,
                          child: Text('Sign Hash'),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _signTransaction,
                          child: Text('Sign TX'),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _createNonce,
                      child: Text('Create Nonce'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDlcTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DLC Operations',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _createDlcSetup,
                          child: Text('Create DLC Setup'),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _createCetAdaptorSigs,
                          child: Text('Create CET Sigs'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_dlcSetup != null) ...[
            SizedBox(height: 16),
            _buildInfoCard('DLC Event ID', _dlcSetup!['eventId']),
            _buildInfoCard('Signing Public Key', _dlcSetup!['signingPublicKey']),
            _buildInfoCard('Nonces', _dlcSetup!['nonces'].join('\n')),
            _buildInfoCard('Signatures', _dlcSetup!['signatures'].join('\n')),
          ],
        ],
      ),
    );
  }

  Widget _buildAddressesTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Address Management',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadAddresses,
                    child: Text('Load Addresses'),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          ..._addresses.map((addr) => Card(
                child: ListTile(
                  title: Text('Index ${addr['index']}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Address: ${addr['address']}'),
                      Text('Public Key: ${addr['publicKey']}'),
                    ],
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: addr['address']!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Address copied to clipboard')),
                      );
                    },
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

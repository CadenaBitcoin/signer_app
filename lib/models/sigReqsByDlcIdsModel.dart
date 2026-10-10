class SigReqsByDlcIdsModel {
  double? timestamp;
  List<Payload>? payload;
  String? message;

  SigReqsByDlcIdsModel({this.timestamp, this.payload, this.message});

  SigReqsByDlcIdsModel.fromJson(Map<String, dynamic> json) {
    timestamp = json['timestamp'];
    if (json['payload'] != null) {
      payload = <Payload>[];
      json['payload'].forEach((v) {
        payload!.add(new Payload.fromJson(v));
      });
    }
    message = json['message'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['timestamp'] = this.timestamp;
    if (this.payload != null) {
      data['payload'] = this.payload!.map((v) => v.toJson()).toList();
    }
    data['message'] = this.message;
    return data;
  }
}

class Payload {
  Funding? funding;
  Funding? refund;
  Cets? cets;

  Payload({this.funding, this.refund, this.cets});

  Payload.fromJson(Map<String, dynamic> json) {
    funding = json['funding'] != null ? new Funding.fromJson(json['funding']) : null;
    refund = json['refund'] != null ? new Funding.fromJson(json['refund']) : null;
    cets = json['cets'] != null ? new Cets.fromJson(json['cets']) : null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    if (this.funding != null) {
      data['funding'] = this.funding!.toJson();
    }
    if (this.refund != null) {
      data['refund'] = this.refund!.toJson();
    }
    if (this.cets != null) {
      data['cets'] = this.cets!.toJson();
    }
    return data;
  }
}

class Funding {
  List<InputReqs>? inputReqs;
  String? tx;
  String? txid;

  Funding({this.inputReqs, this.tx, this.txid});

  Funding.fromJson(Map<String, dynamic> json) {
    if (json['input_reqs'] != null) {
      inputReqs = <InputReqs>[];
      json['input_reqs'].forEach((v) {
        inputReqs!.add(new InputReqs.fromJson(v));
      });
    }
    tx = json['tx'];
    txid = json['txid'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    if (this.inputReqs != null) {
      data['input_reqs'] = this.inputReqs!.map((v) => v.toJson()).toList();
    }
    data['tx'] = this.tx;
    data['txid'] = this.txid;
    return data;
  }
}

class InputReqs {
  int? inputIndex;
  int? signerIndex;
  int? signerIndex4;
  String? signerPubkey;
  String? sighash;
  int? sighashType;

  InputReqs({this.inputIndex, this.signerIndex, this.signerIndex4, this.signerPubkey, this.sighash, this.sighashType});

  InputReqs.fromJson(Map<String, dynamic> json) {
    inputIndex = json['input_index'];
    signerIndex = json['signer_index'];
    signerIndex4 = json['signer_index4'] != null ? json['signer_index4'] : 0;
    signerPubkey = json['signer_pubkey'];
    sighash = json['sighash'];
    sighashType = json['sighash_type'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['input_index'] = this.inputIndex;
    data['signer_index'] = this.signerIndex;
    data['signer_index4'] = this.signerIndex4;
    data['signer_pubkey'] = this.signerPubkey;
    data['sighash'] = this.sighash;
    data['sighash_type'] = this.sighashType;
    return data;
  }
}

class Cets {
  int? numDigits;
  int? numCets;
  String? digitStringTemplate;
  String? oraclePubkey;
  int? signerIndex;
  int? signerIndex4;
  String? signerPubkey;
  String? nonces;
  String? intervalWildcards;
  String? sighashes;

  Cets({this.numDigits, this.numCets, this.digitStringTemplate, this.oraclePubkey, this.signerIndex, this.signerIndex4, this.signerPubkey, this.nonces, this.intervalWildcards, this.sighashes});

  Cets.fromJson(Map<String, dynamic> json) {
    numDigits = json['num_digits'];
    numCets = json['num_cets'];
    digitStringTemplate = json['digit_string_template'];
    oraclePubkey = json['oracle_pubkey'];
    signerIndex = json['signer_index'];
    signerIndex4 = json['signer_index4'] != null ? json['signer_index4'] : 0;
    signerPubkey = json['signer_pubkey'];
    nonces = json['nonces'];
    intervalWildcards = json['interval_wildcards'];
    sighashes = json['sighashes'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['num_digits'] = this.numDigits;
    data['num_cets'] = this.numCets;
    data['digit_string_template'] = this.digitStringTemplate;
    data['oracle_pubkey'] = this.oraclePubkey;
    data['signer_index'] = this.signerIndex;
    data['signer_index4'] = this.signerIndex4;
    data['signer_pubkey'] = this.signerPubkey;
    data['nonces'] = this.nonces;
    data['interval_wildcards'] = this.intervalWildcards;
    data['sighashes'] = this.sighashes;
    return data;
  }
}
